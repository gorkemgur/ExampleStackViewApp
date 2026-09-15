import Foundation

public struct ScanConfiguration: Sendable, Hashable {

    /// How many originals are read at once. Kept low on purpose: the bottleneck is storage
    /// and thermals, not CPU, and a hot phone throttles everything else the user is doing.
    public var maxConcurrentReads: Int
    /// Both fingerprints must be within this to call two photos the same shot.
    public var nearExactDistance: Int
    /// Both fingerprints must be within this for the pair to be worth showing at all.
    public var similarDistance: Int
    /// Feature print distance below which two images are the same shot.
    ///
    /// A different scale from the two above and not convertible to them: those count differing
    /// bits out of 64, this is a squared Euclidean distance in [0, 4].
    public var featurePrintNearExactDistance: Double
    /// Feature print distance below which a pair is worth showing at all.
    ///
    /// **Provisional.** Set from the measurements in `docs/OPPORTUNITIES.md` §9.2, taken on a
    /// Mac against a one-image corpus: a q40 re-encode scores 0.0013, a brutal q15 0.0175, a
    /// 10 % crop 0.0299, a 640 px downscale 0.0367, a 30 % crop 0.1036, a letterboxed copy
    /// 0.1638 — and a different photograph 1.6697. 0.20 clears the worst true match by 1.22x
    /// and sits 5.2x below the nearest false one. Re-measure on a device before believing it.
    public var featurePrintSimilarDistance: Double
    /// Re-encodes keep their framing, so a different aspect ratio means a different crop.
    public var aspectRatioTolerance: Double
    /// How different two videos' proportions may be and still be worth opening.
    ///
    /// Far looser than `aspectRatioTolerance`, because it answers a different question. That
    /// one decides whether a pair is the *same shot*, where 1% is right. This one only decides
    /// whether to spend a decode on them, and a re-export can legitimately change the framing:
    /// 16:9 against 4:3 is 25% and must still be examined, while 16:9 against 9:16 is 69% and
    /// is a portrait video and a landscape one, which is never the same recording.
    ///
    /// Reusing the strict tolerance here threw away every pair that had been reaching the
    /// `.similar` tier — the test for exactly that case is what caught it.
    public var videoShapeTolerance: Double
    /// Seconds two videos may differ by and still be worth comparing frame by frame.
    /// Transcoding shifts a duration slightly; it does not change it.
    public var videoDurationTolerance: Double
    /// Mean frame distance below which two videos are the same footage.
    public var videoAverageDistance: Double
    /// A single frame this far apart vetoes the match, however good the average looked.
    public var videoWorstFrameDistance: Int

    public init(
        maxConcurrentReads: Int = 4,
        nearExactDistance: Int = 6,
        similarDistance: Int = 12,
        featurePrintNearExactDistance: Double = 0.02,
        featurePrintSimilarDistance: Double = 0.20,
        aspectRatioTolerance: Double = 0.01,
        videoShapeTolerance: Double = 0.5,
        videoDurationTolerance: Double = 0.5,
        videoAverageDistance: Double = 8,
        videoWorstFrameDistance: Int = 16
    ) {
        self.maxConcurrentReads = max(1, maxConcurrentReads)
        self.nearExactDistance = nearExactDistance
        self.similarDistance = max(similarDistance, nearExactDistance)
        self.featurePrintNearExactDistance = featurePrintNearExactDistance
        self.featurePrintSimilarDistance = max(featurePrintSimilarDistance, featurePrintNearExactDistance)
        self.aspectRatioTolerance = aspectRatioTolerance
        self.videoShapeTolerance = videoShapeTolerance
        self.videoDurationTolerance = videoDurationTolerance
        self.videoAverageDistance = videoAverageDistance
        self.videoWorstFrameDistance = videoWorstFrameDistance
    }

    public static let `default` = ScanConfiguration()
}

public struct ScanProgress: Sendable, Hashable {

    public enum Stage: Int, Sendable, Hashable, Codable, CaseIterable {
        case bucketing
        case hashing
        case fingerprinting
        case sampling
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
    private let pause: any ScanPausing

    public init(
        analyzer: any AssetAnalyzing,
        configuration: ScanConfiguration = .default,
        throttle: any ScanThrottling = SystemThrottle(),
        pause: any ScanPausing = NeverPaused()
    ) {
        self.analyzer = analyzer
        self.configuration = configuration
        self.throttle = throttle
        self.pause = pause
    }

    public func run(
        items: [MediaItem],
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> ScanResult {

        // `uniquingKeysWith` rather than `uniqueKeysWithValues`, which traps. Two items can
        // arrive with the same id — a folder granted twice under different paths, a bookmark
        // that no longer resolves so the overlap check skips it, a `/private` prefix that
        // defeats a string comparison — and a trap here is a crash inside the engine with the
        // scan already running and a Live Activity on the Lock Screen. The first wins; a
        // duplicate id describes the same file either way.
        let index = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
                let result = await analyzer.imageFingerprint(for: item)
                return (item.id, result)
            }
        )

        var hashes: [String: PerceptualHashes] = [:]
        // Kept beside the hashes rather than replacing them. The hashes are cheap, they are
        // right at short range, and an item whose print could not be produced still has to be
        // matchable — so the print is an extra opinion on the pairs that have one, not a
        // precondition for being looked at.
        var featurePrints: [String: FeaturePrint] = [:]
        for (id, value) in hashResults {
            guard let value else { continue }
            hashes[id] = value.hashes
            if let print = value.featurePrint { featurePrints[id] = print }
        }
        try Task.checkCancellation()

        // 4. Videos that byte equality did not settle. Duration comes for free and a
        // transcode barely moves it, so pairs are proposed on that alone and only the videos
        // with a plausible partner are ever opened and sampled.
        let videoPairs = Self.videoCandidatePairs(
            items.filter { !consumed.contains($0.id) && !cloudOnly.contains($0.id) },
            tolerance: configuration.videoDurationTolerance,
            shapeTolerance: configuration.videoShapeTolerance
        )
        let videoPairIDs = Set(videoPairs.flatMap { [$0.a, $0.b] })
        let videoTargets = items.filter { videoPairIDs.contains($0.id) }

        let signatureResults = try await mapConcurrently(
            videoTargets,
            limit: throttle.concurrencyLimit(base: configuration.maxConcurrentReads),
            progress: { done in
                progress(ScanProgress(stage: .sampling, completed: done, total: videoTargets.count))
            },
            transform: { item in
                let signature = await analyzer.videoSignature(for: item)
                return (item.id, signature)
            }
        )

        var signatures: [String: VideoSignature] = [:]
        for (id, value) in signatureResults {
            if let value { signatures[id] = value }
        }
        try Task.checkCancellation()

        // 5. Candidate lookup through a metric tree, then a second opinion from the other hash.
        progress(ScanProgress(stage: .matching, completed: 0, total: hashes.count))
        var edges = try Self.edges(
            hashes: hashes,
            featurePrints: featurePrints,
            items: index,
            configuration: configuration,
            progress: { done, total in
                progress(ScanProgress(stage: .matching, completed: done, total: total))
            }
        )
        let videoEdges = Self.videoEdges(
            pairs: videoPairs,
            signatures: signatures,
            items: index,
            configuration: configuration
        )
        edges.nearExact += videoEdges.nearExact
        edges.similar += videoEdges.similar
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

        // 6. Decide what survives, and what that would be worth.
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

    /// The most neighbours any one item may contribute.
    ///
    /// Both edge sets used to grow without a ceiling. A camera roll with five thousand
    /// screenshots of the same app screen — common, and precisely the case this app is for —
    /// produces about twelve and a half million edges, each holding two `String` ids: several
    /// gigabytes, and a scan killed by the system somewhere in the middle. The clusterer only
    /// ever reads a seed's neighbours and only the closest of them matter, so keeping the
    /// closest few hundred per item costs nothing anyone can observe and bounds this at
    /// n x 256 instead of n squared.
    static let maximumNeighboursPerItem = 256

    /// A feature print distance, said in the units the rest of the engine speaks.
    ///
    /// `SimilarityEdge.distance` counts differing bits and the clusterer filters on it, so an
    /// edge that came from a print still has to carry a bit count. Widening that Int to a
    /// Double everywhere would touch the clusterer, the video edges and every test that builds
    /// an edge, for the one kind of edge that is not measured in bits.
    ///
    /// Monotone, which is all the clusterer asks of it — it keeps each seed's closest
    /// neighbour. Piecewise, so the two Double thresholds keep meaning what the two Int ones
    /// mean: a pair inside the print's near-exact limit lands inside the bit near-exact limit
    /// whatever either pair is tuned to. One linear map would couple them by their ratio, and
    /// then moving one threshold would silently move the other.
    static func onTheHammingScale(_ distance: Double, configuration: ScanConfiguration) -> Int {
        let near = configuration.featurePrintNearExactDistance
        let similar = configuration.featurePrintSimilarDistance

        if distance <= near {
            let fraction = distance / max(near, .ulpOfOne)
            let bits = fraction * Double(configuration.nearExactDistance)
            return min(configuration.nearExactDistance, max(0, Int(bits.rounded())))
        }

        let fraction = (distance - near) / max(similar - near, .ulpOfOne)
        let span = Double(configuration.similarDistance - configuration.nearExactDistance)
        let bits = Double(configuration.nearExactDistance) + fraction * span
        return min(configuration.similarDistance, max(configuration.nearExactDistance, Int(bits.rounded())))
    }

    static func edges(
        hashes: [String: PerceptualHashes],
        featurePrints: [String: FeaturePrint] = [:],
        items: [String: MediaItem],
        configuration: ScanConfiguration,
        progress: (Int, Int) -> Void = { _, _ in }
    ) throws -> EdgeSets {

        // A flat sweep rather than a BK-tree.
        //
        // The tree was doing no work. Its pruning window is [d-r, d+r], which at the similar
        // threshold of 12 is 25 wide, and 64-bit Hamming distances between unrelated hashes
        // concentrate around 32 give or take four — so the window swallows the whole
        // distribution and the query visits 78-85% of the nodes. It was a linear scan wearing
        // a tree's costs: a dictionary lookup and a node allocation per visit, and every pair
        // discovered twice, once from each end.
        //
        // This is the same comparison over three parallel arrays, each pair looked at once,
        // with the cheap dHash test first so the second hash is only computed for hashes that
        // already passed. Same results, none of the overhead.
        let ordered = hashes.keys.sorted()
        let count = ordered.count
        var dHashes = [UInt64](repeating: 0, count: count)
        var pHashes = [UInt64](repeating: 0, count: count)
        var prints = [FeaturePrint?](repeating: nil, count: count)
        for (index, id) in ordered.enumerated() {
            let hash = hashes[id]!
            dHashes[index] = hash.dHash
            pHashes[index] = hash.pHash
            prints[index] = featurePrints[id]
        }

        var nearExact = Set<SimilarityEdge>()
        var similar = Set<SimilarityEdge>()

        for outer in 0..<count {
            // The longest stretch of the scan, and until now the one stretch with no
            // cancellation check and no progress in it: the bar sat at "matching 0 of n" for
            // the whole of it and the stop button did nothing. `run` claims every stage is
            // cancellable; this is where that became true.
            if outer % 128 == 0 {
                try Task.checkCancellation()
                progress(outer, count)
            }

            var neighbours: [(index: Int, distance: Int, isNearExact: Bool)] = []

            for inner in (outer + 1)..<count {
                // When both sides have a feature print, the print is the judgement — not a
                // second opinion on a pair the hashes already liked.
                //
                // It has to be this way round. A 10 % crop scores 16 bits against dHash and the
                // similar threshold is 12, so a hash gate would throw that pair away before the
                // print ever saw it — and the crop is the entire reason the print is here
                // (`docs/OPPORTUNITIES.md` §9.1). The cost is that a pair with two prints is
                // measured rather than dismissed on a 64-bit XOR; `proximity(within:)` stops
                // the moment the running sum passes the threshold, which for two unrelated
                // photographs happens inside the first few dozen of 768 elements.
                if let left = prints[outer], let right = prints[inner] {
                    switch left.proximity(to: right, within: configuration.featurePrintSimilarDistance) {
                    case let .within(distance):
                        neighbours.append((
                            inner,
                            Self.onTheHammingScale(distance, configuration: configuration),
                            distance <= configuration.featurePrintNearExactDistance
                        ))
                        continue
                    case .beyond:
                        continue
                    case .incomparable:
                        // Two revisions, or two lengths. The print has no opinion, which is a
                        // different thing from a bad one: fall through to the hashes rather
                        // than veto a pair because a cache entry was written by an older build.
                        break
                    }
                }

                let dDistance = hammingDistance(dHashes[outer], dHashes[inner])
                guard dDistance <= configuration.similarDistance else { continue }

                // The second fingerprint is an independent opinion: dHash tracks local
                // gradients, pHash tracks low-frequency structure. Requiring both to agree is
                // what keeps unrelated photos out of a deletion list.
                let pDistance = hammingDistance(pHashes[outer], pHashes[inner])
                guard pDistance <= configuration.similarDistance else { continue }

                let distance = max(dDistance, pDistance)
                neighbours.append((inner, distance, distance <= configuration.nearExactDistance))
            }

            if neighbours.count > Self.maximumNeighboursPerItem {
                neighbours.sort {
                    $0.distance == $1.distance ? $0.index < $1.index : $0.distance < $1.distance
                }
                neighbours.removeLast(neighbours.count - Self.maximumNeighboursPerItem)
            }

            let id = ordered[outer]
            for neighbour in neighbours {
                let otherID = ordered[neighbour.index]
                let edge = SimilarityEdge(a: id, b: otherID, distance: neighbour.distance)

                if neighbour.isNearExact,
                   sameFraming(items[id], items[otherID], tolerance: configuration.aspectRatioTolerance) {
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

    /// Pairs of videos close enough in length *and* shape to be worth opening.
    ///
    /// Sorted once and swept, so this costs a sort rather than a comparison of every video
    /// against every other one. Duration is metadata the library already has; sampling frames
    /// is not, and this is what keeps the expensive half off most of the library.
    ///
    /// The shape half was missing, and it is the half that matters at scale: a camera roll of
    /// three thousand fifteen-second clips — app exports, screen recordings, anything with a
    /// fixed length — all fall inside the duration window of each other, so the sweep produced
    /// four and a half million pairs and four and a half million frame comparisons. Two videos
    /// of different proportions are not the same recording, and the library knows their
    /// proportions without opening anything.
    static func videoCandidatePairs(
        _ items: [MediaItem],
        tolerance: Double,
        shapeTolerance: Double = ScanConfiguration.default.videoShapeTolerance
    ) -> [SimilarityEdge] {
        let videos = items
            .filter { $0.kind == .video && $0.duration > 0 }
            .sorted { $0.duration == $1.duration ? $0.id < $1.id : $0.duration < $1.duration }

        var pairs: [SimilarityEdge] = []
        for outer in videos.indices {
            var inner = outer + 1
            while inner < videos.count,
                  videos[inner].duration - videos[outer].duration <= tolerance {
                defer { inner += 1 }
                guard couldShareFraming(
                    videos[outer],
                    videos[inner],
                    tolerance: shapeTolerance
                ) else { continue }
                pairs.append(SimilarityEdge(a: videos[outer].id, b: videos[inner].id, distance: 0))
            }
        }
        return pairs
    }

    static func videoEdges(
        pairs: [SimilarityEdge],
        signatures: [String: VideoSignature],
        items: [String: MediaItem],
        configuration: ScanConfiguration
    ) -> EdgeSets {

        var nearExact: [SimilarityEdge] = []
        var similar: [SimilarityEdge] = []

        for pair in pairs {
            guard
                let left = signatures[pair.a],
                let right = signatures[pair.b],
                let comparison = VideoMatcher.compare(left, right)
            else {
                continue
            }

            guard VideoMatcher.isDuplicate(
                comparison,
                maximumAverage: configuration.videoAverageDistance,
                maximumWorstFrame: configuration.videoWorstFrameDistance
            ) else {
                continue
            }

            let distance = Int(comparison.averageDistance.rounded())
            let edge = SimilarityEdge(a: pair.a, b: pair.b, distance: distance)

            if distance <= configuration.nearExactDistance,
               sameFraming(items[pair.a], items[pair.b], tolerance: configuration.aspectRatioTolerance) {
                nearExact.append(edge)
            } else {
                similar.append(edge)
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

    /// `sameFraming`, but unknown proportions do not count as different.
    ///
    /// The two are used for opposite purposes and need opposite defaults. Deciding whether a
    /// pair is near-exact, not knowing is a reason to say no — that is `sameFraming`, and it
    /// stays strict. Deciding whether a pair is worth *opening*, not knowing is not evidence of
    /// anything, and answering no would throw the pair away unexamined. A folder video carries
    /// no dimensions until something reads it, so the strict version here would have excluded
    /// every file-to-file video pair in the app.
    static func couldShareFraming(_ lhs: MediaItem?, _ rhs: MediaItem?, tolerance: Double) -> Bool {
        guard let lhs, let rhs else { return false }
        guard lhs.aspectRatio > 0, rhs.aspectRatio > 0 else { return true }
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

        let pause = self.pause
        var results = [Output?](repeating: nil, count: elements.count)
        let window = max(1, min(limit, elements.count))

        try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            var next = 0
            var finished = 0

            for _ in 0..<window {
                let index = next
                let element = elements[index]
                group.addTask {
                    await pause.waitUntilResumed()
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
                        await pause.waitUntilResumed()
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
