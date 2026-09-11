import Foundation

public struct ScanConfiguration: Sendable, Hashable {

    /// How many originals are read at once. Kept low on purpose: the bottleneck is storage
    /// and thermals, not CPU, and a hot phone throttles everything else the user is doing.
    public var maxConcurrentReads: Int
    /// Both fingerprints must be within this to call two photos the same shot.
    public var nearExactDistance: Int
    /// Both fingerprints must be within this for the pair to be worth showing at all.
    public var similarDistance: Int
    /// Re-encodes keep their framing, so a different aspect ratio means a different crop.
    public var aspectRatioTolerance: Double

    public init(
        maxConcurrentReads: Int = 4,
        nearExactDistance: Int = 6,
        similarDistance: Int = 12,
        aspectRatioTolerance: Double = 0.01
    ) {
        self.maxConcurrentReads = max(1, maxConcurrentReads)
        self.nearExactDistance = nearExactDistance
        self.similarDistance = max(similarDistance, nearExactDistance)
        self.aspectRatioTolerance = aspectRatioTolerance
    }

    public static let `default` = ScanConfiguration()
}

public struct ScanProgress: Sendable, Hashable {

    public enum Stage: Int, Sendable, Hashable, CaseIterable {
        case bucketing
        case hashing
        case fingerprinting
        case matching
        case planning
    }

    public let stage: Stage
    public let completed: Int
    public let total: Int

    public init(stage: Stage, completed: Int, total: Int) {
        self.stage = stage
        self.completed = completed
        self.total = total
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(completed) / Double(total), 1)
    }
}

public struct ScanResult: Sendable {

    public let items: [String: MediaItem]
    public let groups: [DuplicateGroup]
    public let decisions: [GroupDecision]
    public let candidates: [DeletionCandidate]
    /// Items whose originals are in iCloud and were therefore never read.
    public let cloudOnlyIDs: Set<String>

    public init(
        items: [String: MediaItem],
        groups: [DuplicateGroup],
        decisions: [GroupDecision],
        candidates: [DeletionCandidate],
        cloudOnlyIDs: Set<String>
    ) {
        self.items = items
        self.groups = groups
        self.decisions = decisions
        self.candidates = candidates
        self.cloudOnlyIDs = cloudOnlyIDs
    }

    public static let empty = ScanResult(
        items: [:], groups: [], decisions: [], candidates: [], cloudOnlyIDs: []
    )

    public var tierSummaries: [TierSummary] { BudgetPlanner.summaries(for: candidates) }

    public var reclaimableBytes: Int64 { candidates.reduce(Int64(0)) { $0 + $1.bytes } }
}

/// Finds duplicates, in the order that does the least work.
///
/// Stage 1 groups by metadata alone, which is free and throws away the overwhelming majority
/// of a library. Only the survivors get their bytes read. Only after that do images get
/// fingerprinted, and fingerprints are compared through a metric tree rather than pairwise.
/// Every stage is cancellable, because a scan the user cannot stop is a scan they will force
/// quit halfway through.
public struct ScanPipeline: Sendable {

    private let analyzer: any AssetAnalyzing
    private let configuration: ScanConfiguration
    private let throttle: any ScanThrottling

    public init(
        analyzer: any AssetAnalyzing,
        configuration: ScanConfiguration = .default,
        throttle: any ScanThrottling = SystemThrottle()
    ) {
        self.analyzer = analyzer
        self.configuration = configuration
        self.throttle = throttle
    }

    public func run(
        items: [MediaItem],
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> ScanResult {

        let index = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        guard !items.isEmpty else { return .empty }

        // Bound to locals so the concurrent closures below capture plain values.
        let analyzer = self.analyzer
        let configuration = self.configuration

        // Re-read once per stage rather than per item: a device that heats up mid-scan slows
        // down at the next stage boundary, without paying for a check on every read.
        let readLimit = throttle.concurrencyLimit(base: configuration.maxConcurrentReads)

        // 1. Metadata buckets. Identical originals always agree on kind, pixels and size.
        progress(ScanProgress(stage: .bucketing, completed: 0, total: items.count))

        // An item the source already knows is not on this device is set aside before any work
        // is scheduled against it. Reading it would mean a download, and the point of the scan
        // is to free space, not to spend someone's data plan filling it.
        var cloudOnly = Set(items.filter { !$0.isLocallyAvailable }.map(\.id))
        let localItems = items.filter { $0.isLocallyAvailable }

        let suspects = Self.metadataSuspects(localItems)
        try Task.checkCancellation()
        progress(ScanProgress(stage: .bucketing, completed: items.count, total: items.count))

        // 2. Read and digest only the suspects.
        var digests: [String: ContentDigest] = [:]

        let digestResults = try await mapConcurrently(
            suspects,
            limit: readLimit,
            progress: { done in
                progress(ScanProgress(stage: .hashing, completed: done, total: suspects.count))
            },
            transform: { item in
                let result = await analyzer.contentDigest(for: item)
                return (item.id, result)
            }
        )

        for (id, result) in digestResults {
            switch result {
            case let .digest(digest): digests[id] = digest
            case .cloudOnly: cloudOnly.insert(id)
            case .unavailable: break
            }
        }

        let exactGroups = DuplicateClusterer.exactGroups(keys: digests)
        var consumed = Set(exactGroups.flatMap(\.itemIDs))
        try Task.checkCancellation()

        // 3. Fingerprint the images that are still unaccounted for.
        let fingerprintTargets = items.filter {
            $0.kind == .image && !consumed.contains($0.id) && !cloudOnly.contains($0.id)
        }

        let hashResults = try await mapConcurrently(
            fingerprintTargets,
            limit: throttle.concurrencyLimit(base: configuration.maxConcurrentReads),
            progress: { done in
                progress(ScanProgress(stage: .fingerprinting, completed: done, total: fingerprintTargets.count))
            },
            transform: { item in
                let result = await analyzer.perceptualHashes(for: item)
                return (item.id, result)
            }
        )

        var hashes: [String: PerceptualHashes] = [:]
        for (id, value) in hashResults {
            if let value { hashes[id] = value }
        }
        try Task.checkCancellation()

        // 4. Candidate lookup through a metric tree, then a second opinion from the other hash.
        progress(ScanProgress(stage: .matching, completed: 0, total: hashes.count))
        let edges = Self.edges(hashes: hashes, items: index, configuration: configuration)
        try Task.checkCancellation()

        let ranks = KeeperScorer.globalRanks(for: items)

        // Tighter evidence forms groups first, so a photo lands in the most confident group
        // it qualifies for and — because each stage excludes what the previous one took —
        // in exactly one group overall.
        let nearExactGroups = DuplicateClusterer.similarGroups(
            edges: edges.nearExact.filter { !consumed.contains($0.a) && !consumed.contains($0.b) },
            rank: ranks,
            maxDistance: configuration.nearExactDistance,
            relation: .nearExact
        )
        consumed.formUnion(nearExactGroups.flatMap(\.itemIDs))

        let similarGroups = DuplicateClusterer.similarGroups(
            edges: edges.similar.filter { !consumed.contains($0.a) && !consumed.contains($0.b) },
            rank: ranks,
            maxDistance: configuration.similarDistance,
            relation: .similar
        )

        progress(ScanProgress(stage: .matching, completed: hashes.count, total: hashes.count))
        try Task.checkCancellation()

        // 5. Decide what survives, and what that would be worth.
        progress(ScanProgress(stage: .planning, completed: 0, total: 1))
        let groups = exactGroups + nearExactGroups + similarGroups
        let decisions = CleanupPlanner.decide(groups: groups, items: index)
        let candidates = TierClassifier.candidates(decisions: decisions, groups: groups, items: index)
        progress(ScanProgress(stage: .planning, completed: 1, total: 1))

        return ScanResult(
            items: index,
            groups: groups,
            decisions: decisions,
            candidates: candidates,
            cloudOnlyIDs: cloudOnly
        )
    }

    // MARK: - Stages

    /// Items sharing kind, pixel dimensions and byte size with at least one other item.
    /// Anything unique on those three cannot be a byte-identical duplicate of anything.
    static func metadataSuspects(_ items: [MediaItem]) -> [MediaItem] {
        var buckets: [String: [MediaItem]] = [:]
        for item in items where item.byteSize > 0 {
            let key = "\(item.kind.rawValue)|\(item.pixelWidth)x\(item.pixelHeight)|\(item.byteSize)"
            buckets[key, default: []].append(item)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .flatMap { $0 }
            .sorted { $0.id < $1.id }
    }

    struct EdgeSets: Sendable {
        var nearExact: [SimilarityEdge] = []
        var similar: [SimilarityEdge] = []
    }

    static func edges(
        hashes: [String: PerceptualHashes],
        items: [String: MediaItem],
        configuration: ScanConfiguration
    ) -> EdgeSets {

        var tree = BKTree()
        for (id, hash) in hashes.sorted(by: { $0.key < $1.key }) {
            tree.insert(value: hash.dHash, id: id)
        }

        var nearExact = Set<SimilarityEdge>()
        var similar = Set<SimilarityEdge>()

        for (id, hash) in hashes.sorted(by: { $0.key < $1.key }) {
            for hit in tree.query(value: hash.dHash, maxDistance: configuration.similarDistance) {
                guard hit.id != id else { continue }
                guard let otherHash = hashes[hit.id] else { continue }

                // The second fingerprint is an independent opinion: dHash tracks local
                // gradients, pHash tracks low-frequency structure. Requiring both to agree is
                // what keeps unrelated photos out of a deletion list.
                let pDistance = hammingDistance(hash.pHash, otherHash.pHash)
                guard pDistance <= configuration.similarDistance else { continue }

                let distance = max(hit.distance, pDistance)
                let edge = SimilarityEdge(a: id, b: hit.id, distance: distance)

                if distance <= configuration.nearExactDistance,
                   sameFraming(items[id], items[hit.id], tolerance: configuration.aspectRatioTolerance) {
                    nearExact.insert(edge)
                } else {
                    similar.insert(edge)
                }
            }
        }

        return EdgeSets(
            nearExact: nearExact.sorted { $0.a == $1.a ? $0.b < $1.b : $0.a < $1.a },
            similar: similar.sorted { $0.a == $1.a ? $0.b < $1.b : $0.a < $1.a }
        )
    }

    static func sameFraming(_ lhs: MediaItem?, _ rhs: MediaItem?, tolerance: Double) -> Bool {
        guard let lhs, let rhs, lhs.aspectRatio > 0, rhs.aspectRatio > 0 else { return false }
        return abs(lhs.aspectRatio - rhs.aspectRatio) / max(lhs.aspectRatio, rhs.aspectRatio) <= tolerance
    }

    // MARK: - Bounded concurrency

    /// Runs `transform` over `elements` with at most `limit` in flight, preserving order and
    /// reporting completions as they land.
    private func mapConcurrently<Element: Sendable, Output: Sendable>(
        _ elements: [Element],
        limit: Int,
        progress: @escaping @Sendable (Int) -> Void,
        transform: @escaping @Sendable (Element) async -> Output
    ) async throws -> [Output] {

        guard !elements.isEmpty else { return [] }
        progress(0)

        var results = [Output?](repeating: nil, count: elements.count)
        let window = max(1, min(limit, elements.count))

        try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            var next = 0
            var finished = 0

            for _ in 0..<window {
                let index = next
                let element = elements[index]
                group.addTask {
                    let output = await transform(element)
                    return (index, output)
                }
                next += 1
            }

            while let (index, value) = try await group.next() {
                results[index] = value
                finished += 1
                progress(finished)

                try Task.checkCancellation()

                if next < elements.count {
                    let index = next
                    let element = elements[index]
                    group.addTask {
                        let output = await transform(element)
                        return (index, output)
                    }
                    next += 1
                }
            }
        }

        return results.compactMap { $0 }
    }
}
