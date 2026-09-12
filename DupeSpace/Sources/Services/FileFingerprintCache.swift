import Foundation
import DupeCore

/// The fingerprint cache, kept on disk between launches.
///
/// Wraps the in-memory actor rather than reimplementing it: the interesting behaviour —
/// when a record is stale, what a partial write does to its siblings — lives in one place and
/// is tested there. This adds only "read it at startup, write it when it changes".
actor FileFingerprintCache: FingerprintCaching {

    private let fileURL: URL
    private let inner: FingerprintCache
    private var isDirty = false
    private var hasLoaded = false

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = base.appendingPathComponent("DupeSpace", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("fingerprints.json")
        }
        inner = FingerprintCache()
    }

    func record(for id: String) async -> FingerprintRecord? {
        await loadIfNeeded()
        return await inner.record(for: id)
    }

    func store(digest: ContentDigest, for id: String, contentVersion: String) async {
        await loadIfNeeded()
        await inner.store(digest: digest, for: id, contentVersion: contentVersion)
        isDirty = true
    }

    func store(hashes: PerceptualHashes, for id: String, contentVersion: String) async {
        await loadIfNeeded()
        await inner.store(hashes: hashes, for: id, contentVersion: contentVersion)
        isDirty = true
    }

    func store(signature: VideoSignature, for id: String, contentVersion: String) async {
        await loadIfNeeded()
        await inner.store(signature: signature, for: id, contentVersion: contentVersion)
        isDirty = true
    }

    func prune(keeping ids: Set<String>) async {
        await loadIfNeeded()
        await inner.prune(keeping: ids)
        isDirty = true
    }

    func snapshot() async -> [String: FingerprintRecord] {
        await loadIfNeeded()
        return await inner.snapshot()
    }

    /// Writes only if something changed. Called when a scan finishes rather than on every
    /// fingerprint: fifty thousand writes to serialise the same file is not a cache, it is a
    /// way to make scanning slower than not caching at all.
    func flush() async {
        guard isDirty else { return }
        let records = await inner.snapshot()

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(records) {
            try? data.write(to: fileURL, options: .atomic)
            isDirty = false
        }
    }

    /// A missing or corrupt file is an empty cache, not an error: the worst it costs is one
    /// slow scan, and refusing to scan would be worse.
    private func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        guard
            let data = try? Data(contentsOf: fileURL),
            let records = try? JSONDecoder().decode([String: FingerprintRecord].self, from: data)
        else {
            return
        }

        for (id, record) in records {
            if let digest = record.digest {
                await inner.store(digest: digest, for: id, contentVersion: record.contentVersion)
            }
            if let hashes = record.hashes {
                await inner.store(hashes: hashes, for: id, contentVersion: record.contentVersion)
            }
            if let signature = record.signature {
                await inner.store(signature: signature, for: id, contentVersion: record.contentVersion)
            }
        }
    }
}
