import Foundation

/// Everything expensive that was ever computed about one item.
public struct FingerprintRecord: Sendable, Hashable, Codable {

    /// The item's `contentVersion` when these were computed. Anything else and they are stale.
    public var contentVersion: String
    public var digest: ContentDigest?
    public var hashes: PerceptualHashes?
    public var signature: VideoSignature?

    public init(
        contentVersion: String,
        digest: ContentDigest? = nil,
        hashes: PerceptualHashes? = nil,
        signature: VideoSignature? = nil
    ) {
        self.contentVersion = contentVersion
        self.digest = digest
        self.hashes = hashes
        self.signature = signature
    }

    public var isEmpty: Bool { digest == nil && hashes == nil && signature == nil }
}

public protocol FingerprintCaching: Sendable {
    func record(for id: String) async -> FingerprintRecord?
    func store(digest: ContentDigest, for id: String, contentVersion: String) async
    func store(hashes: PerceptualHashes, for id: String, contentVersion: String) async
    func store(signature: VideoSignature, for id: String, contentVersion: String) async
    /// Forgets everything not in `ids`. Items that left the library take their entries with them.
    func prune(keeping ids: Set<String>) async
    func snapshot() async -> [String: FingerprintRecord]
}

/// The cache itself.
public actor FingerprintCache: FingerprintCaching {

    private var records: [String: FingerprintRecord]

    public init(records: [String: FingerprintRecord] = [:]) {
        self.records = records
    }

    public func record(for id: String) -> FingerprintRecord? { records[id] }

    public func store(digest: ContentDigest, for id: String, contentVersion: String) {
        var record = current(id: id, contentVersion: contentVersion)
        record.digest = digest
        records[id] = record
    }

    public func store(hashes: PerceptualHashes, for id: String, contentVersion: String) {
        var record = current(id: id, contentVersion: contentVersion)
        record.hashes = hashes
        records[id] = record
    }

    public func store(signature: VideoSignature, for id: String, contentVersion: String) {
        var record = current(id: id, contentVersion: contentVersion)
        record.signature = signature
        records[id] = record
    }

    public func prune(keeping ids: Set<String>) {
        records = records.filter { ids.contains($0.key) }
    }

    public func snapshot() -> [String: FingerprintRecord] { records }

    public var count: Int { records.count }

    /// An entry whose version no longer matches is thrown away rather than merged into: the
    /// bytes changed, so every fingerprint held against it describes something that is gone.
    private func current(id: String, contentVersion: String) -> FingerprintRecord {
        if let existing = records[id], existing.contentVersion == contentVersion {
            return existing
        }
        return FingerprintRecord(contentVersion: contentVersion)
    }
}

/// Wraps an analyzer so work already done is never done again.
///
/// A library does not change much between scans. Without this, the second scan of fifty
/// thousand photos costs exactly as much as the first, which is the difference between a
/// feature people use and one they run once.
public struct CachingAnalyzer: AssetAnalyzing {

    private let base: any AssetAnalyzing
    private let cache: any FingerprintCaching

    public init(base: any AssetAnalyzing, cache: any FingerprintCaching) {
        self.base = base
        self.cache = cache
    }

    public func contentDigest(for item: MediaItem) async -> ContentDigestResult {
        if let cached = await usableRecord(for: item)?.digest {
            return .digest(cached)
        }

        let result = await base.contentDigest(for: item)
        if case let .digest(digest) = result {
            await cache.store(digest: digest, for: item.id, contentVersion: item.contentVersion)
        }
        return result
    }

    public func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
        if let cached = await usableRecord(for: item)?.hashes {
            return cached
        }

        let hashes = await base.perceptualHashes(for: item)
        if let hashes {
            await cache.store(hashes: hashes, for: item.id, contentVersion: item.contentVersion)
        }
        return hashes
    }

    public func videoSignature(for item: MediaItem) async -> VideoSignature? {
        if let cached = await usableRecord(for: item)?.signature {
            return cached
        }

        let signature = await base.videoSignature(for: item)
        if let signature {
            await cache.store(signature: signature, for: item.id, contentVersion: item.contentVersion)
        }
        return signature
    }

    private func usableRecord(for item: MediaItem) async -> FingerprintRecord? {
        guard let record = await cache.record(for: item.id) else { return nil }
        return record.contentVersion == item.contentVersion ? record : nil
    }
}
