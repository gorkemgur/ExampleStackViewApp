import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import DupeCore

/// Reads granted files off disk for the scan.
final class FileAssetAnalyzer: AssetAnalyzing {

    private static let chunkSize = 1 << 20

    private let registry: any FolderRegistering

    init(registry: any FolderRegistering) {
        self.registry = registry
    }

    func contentDigest(for item: MediaItem) async -> ContentDigestResult {
        guard item.isLocallyAvailable else { return .cloudOnly }
        let registry = self.registry
        let id = item.id

        return await Task.detached(priority: .utility) {
            FileMediaLibrary.withFile(itemID: id, registry: registry) { url in
                Self.digest(of: url)
            } ?? .unavailable
        }.value
    }

    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
        guard item.kind == .image, item.isLocallyAvailable else { return nil }
        let registry = self.registry
        let id = item.id

        return await Task.detached(priority: .utility) {
            FileMediaLibrary.withFile(itemID: id, registry: registry) { url in
                Self.hashes(of: url)
            } ?? nil
        }.value
    }

    func videoSignature(for item: MediaItem) async -> VideoSignature? {
        guard item.kind == .video, item.isLocallyAvailable else { return nil }

        return await FileMediaLibrary.withFileAsync(itemID: item.id, registry: registry) { url in
            await VideoFrameSampler.signature(for: AVURLAsset(url: url))
        }
    }

    // MARK: - Work

    /// Hashes in chunks so a multi-gigabyte file never lands in memory at once.
    static func digest(of url: URL) -> ContentDigestResult {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unavailable }
        defer { try? handle.close() }

        var digest = StreamingDigest()
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            digest.update(chunk)
        }
        return .digest(digest.finalized())
    }

    /// Decodes a thumbnail rather than the whole image: a 50-megapixel file does not need to
    /// be unpacked in full to produce a 64-pixel fingerprint.
    static func hashes(of url: URL) -> PerceptualHashes? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return hashes(from: source)
    }

    /// The same, for bytes already in hand.
    ///
    /// `PhotoKitAssetAnalyzer` falls back to this when `PHImageManager` hands it nothing it
    /// can hash, so a photograph in the library and the same photograph in a folder go through
    /// one decoder rather than two. That matters more than it looks: the matcher compares
    /// every fingerprint against every other, photo-library items and folder items in the same
    /// sweep, so two downsamplers meant the same picture could fail to match itself across the
    /// two halves of this app.
    static func hashes(of data: Data) -> PerceptualHashes? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return hashes(from: source)
    }

    /// The decode both of those share.
    ///
    /// `renderSize * 4` and not `renderSize`: the fingerprint is 64 across, and handing the
    /// hasher a buffer that was *already* 64 across leaves it nothing to average away. Four
    /// times over is enough headroom that two encodings of one picture land on the same
    /// fingerprint, and still small enough that nothing large is ever unpacked.
    private static func hashes(from source: CGImageSource) -> PerceptualHashes? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: GrayImageRenderer.renderSize * 4
        ]

        guard
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let gray = GrayImageRenderer.render(thumbnail)
        else {
            return nil
        }

        return PerceptualHashes(
            dHash: PerceptualHasher.dHash(gray),
            pHash: PerceptualHasher.pHash(gray)
        )
    }
}

/// Deletes granted files.
///
/// Coordinated, because a folder in iCloud Drive has other processes watching it, and an
/// uncoordinated delete there is how a sync conflict becomes a lost file.
final class FileDeleter: MediaDeleting {

    private let registry: any FolderRegistering

    init(registry: any FolderRegistering) {
        self.registry = registry
    }

    func delete(ids: [String], expecting stamps: [String: FileStamp]) async throws -> DeletionOutcome {
        try await delete(ids: ids, expecting: stamps, onProgress: { _ in })
    }

    /// One file is one step, and every one of them is real: this half is a loop, not an atomic
    /// change, and each turn of it removes something that is gone for good.
    func delete(
        ids: [String],
        expecting stamps: [String: FileStamp],
        onProgress: @escaping DeletionProgressHandler
    ) async throws -> DeletionOutcome {
        let registry = self.registry
        let total = ids.count

        let result: (deleted: [String], skipped: [String]) = await Task.detached(priority: .userInitiated) {
            var removed: [String] = []
            var refused: [String] = []
            var settled = 0

            for id in ids {
                let outcome = FileMediaLibrary.withFile(itemID: id, registry: registry) { url -> Bool? in
                    // `nil` means "not this file": the deletion is refused rather than failing,
                    // and the caller is told so it can say which.
                    //
                    // A missing stamp refuses too. This used to read `if let expected = …`,
                    // which meant no stamp, no check, delete — the irreversible half of the app
                    // failing open on the one guard standing between it and a file that was
                    // replaced after the scan read it. `delete(ids:)` without stamps is part of
                    // the protocol, so that path is one call site away at all times.
                    guard let expected = stamps[id], Self.stillMatches(expected, at: url) else {
                        return nil
                    }

                    var success = false
                    var coordinationError: NSError?

                    NSFileCoordinator().coordinate(
                        writingItemAt: url,
                        options: .forDeleting,
                        error: &coordinationError
                    ) { target in
                        success = (try? FileManager.default.removeItem(at: target)) != nil
                    }

                    // A coordination failure is a refusal, not a silent nothing. It used to
                    // return `false`, which fell through to `default: break` and was reported
                    // to the user as "already gone" — the one wording that is certainly wrong
                    // when the file is still sitting there.
                    guard coordinationError == nil else { return nil }
                    return success
                }

                switch outcome {
                case .some(.some(true)):
                    removed.append(id)
                case .some(.none):
                    // The file is not the one the scan read, or the coordinator refused.
                    refused.append(id)
                case .none:
                    // The folder grant would not resolve, so nothing was even looked at.
                    // Reporting this as "already gone" would be a guess about a file the app
                    // could not open.
                    refused.append(id)
                case .some(.some(false)):
                    // The removal itself failed, which for a file that was there a moment ago
                    // almost always means it is not there now. That is what `missingCount`
                    // says, and it is left to say it.
                    break
                }

                // After the switch, not before: a step is reported once the file's fate is
                // settled, whichever way it went. Reporting on entry would have the screen
                // counting away files it had not looked at yet.
                settled += 1
                onProgress(
                    DeletionProgress(
                        stage: .files,
                        settled: settled,
                        total: total,
                        isDeterminate: total > 1
                    )
                )
            }
            return (removed, refused)
        }.value

        return DeletionOutcome(
            requestedIDs: ids,
            deletedIDs: result.deleted,
            skippedIDs: result.skipped
        )
    }

    /// Whether the file on disk is still the one the scan read.
    ///
    /// A scan decides; the user acts later. In between a file can be replaced by something else
    /// with the same name, and nothing in the identifier would change. Size and modification
    /// date are what a stat can answer, and between them they catch a rewritten file.
    private static func stillMatches(_ expected: FileStamp, at url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let size = values.fileSize
        else {
            return false
        }
        return expected.matches(
            byteSize: Int64(size),
            modificationDate: values.contentModificationDate
        )
    }
}
