import Foundation
import DupeCore

/// The fingerprint cache, kept on disk between launches.
///
/// Holds its records directly rather than delegating to another actor. Delegating meant the
/// load had to await mid-flight, which let a second scan task in on a half-filled cache and
/// let the replay overwrite freshly computed records with stale ones from disk.
actor FileFingerprintCache: FingerprintCaching {

    private let fileURL: URL
    private var records: [String: FingerprintRecord] = [:]
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
            self.fileURL = directory.appendingPathComponent("fingerprints.bin")

            // The JSON this replaces. Nothing reads it any more and `fp3` invalidated every
            // record in it, so it is pure dead weight — and on a large library it is hundreds
            // of megabytes of it. An app that asks people to free space does not leave that
            // behind.
            let legacy = directory.appendingPathComponent("fingerprints.json")
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    func record(for id: String) -> FingerprintRecord? {
        loadIfNeeded()
        return records[id]
    }

    func store(digest: ContentDigest, for id: String, contentVersion: String) {
        loadIfNeeded()
        var record = FingerprintRecord.base(from: records[id], contentVersion: contentVersion)
        record.digest = digest
        records[id] = record
        isDirty = true
    }

    func store(hashes: PerceptualHashes, for id: String, contentVersion: String) {
        loadIfNeeded()
        var record = FingerprintRecord.base(from: records[id], contentVersion: contentVersion)
        record.hashes = hashes
        records[id] = record
        isDirty = true
    }

    func store(fingerprint: ImageFingerprint, for id: String, contentVersion: String) {
        loadIfNeeded()
        var record = FingerprintRecord.base(from: records[id], contentVersion: contentVersion)
        record.hashes = fingerprint.hashes
        // Only when there is one, so a source without Vision behind it cannot spend a print the
        // library has already paid twenty-seven milliseconds for.
        if let print = fingerprint.featurePrint { record.featurePrint = print }
        records[id] = record
        isDirty = true
    }

    func store(signature: VideoSignature, for id: String, contentVersion: String) {
        loadIfNeeded()
        var record = FingerprintRecord.base(from: records[id], contentVersion: contentVersion)
        record.signature = signature
        records[id] = record
        isDirty = true
    }

    func prune(keeping ids: Set<String>) {
        loadIfNeeded()
        records = records.filter { ids.contains($0.key) }
        isDirty = true
    }

    func snapshot() -> [String: FingerprintRecord] {
        loadIfNeeded()
        return records
    }

    /// Writes only if something changed, and only when asked. Serialising the whole file after
    /// every fingerprint would cost more than the cache saves.
    func flush() {
        guard isDirty else { return }
        try? FingerprintArchive.data(for: records).write(to: fileURL, options: .atomic)
        isDirty = false
    }

    /// Synchronous on purpose: within an actor, code that never awaits cannot be interleaved
    /// with, so no caller can observe a half-loaded cache.
    ///
    /// A missing or corrupt file is an empty cache, not an error: the worst that costs is one
    /// slow scan, and refusing to scan would be worse.
    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        guard
            let data = try? Data(contentsOf: fileURL),
            let stored = FingerprintArchive.records(from: data)
        else {
            return
        }

        // Anything computed before the load wins: it describes the library as it is now.
        records = stored.merging(records) { _, fresher in fresher }
    }
}
