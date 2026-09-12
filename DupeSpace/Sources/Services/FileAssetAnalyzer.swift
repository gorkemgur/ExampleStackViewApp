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
        guard
            let parsed = FileItemID.parse(item.id),
            let folder = registry.folders().first(where: { $0.id == parsed.folderID })
        else {
            return nil
        }

        return await FolderAccess.withFolderAsync(folder) { root in
            await VideoFrameSampler.signature(
                for: AVURLAsset(url: root.appendingPathComponent(parsed.relativePath))
            )
        } ?? nil
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
        let registry = self.registry

        let result: (deleted: [String], skipped: [String]) = await Task.detached(priority: .userInitiated) {
            var removed: [String] = []
            var refused: [String] = []

            for id in ids {
                let outcome = FileMediaLibrary.withFile(itemID: id, registry: registry) { url -> Bool? in
                    // `nil` means "not this file": the deletion is refused rather than failing,
                    // and the caller is told so it can say which.
                    if let expected = stamps[id], !Self.stillMatches(expected, at: url) {
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

                    return success && coordinationError == nil
                }

                switch outcome {
                case .some(.some(true)): removed.append(id)
                case .some(.none): refused.append(id)
                default: break
                }
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
