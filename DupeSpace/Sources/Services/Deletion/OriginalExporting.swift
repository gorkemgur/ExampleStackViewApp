import Foundation
import Photos
import DupeCore

/// What an export actually managed to write.
struct ExportReceipt: Sendable, Equatable {
    /// The folder the export was written into, by name — the path is the user's business and
    /// says nothing useful on screen.
    let folderName: String
    let exportedIDs: [String]
    /// Originals that could not be written: an iCloud-only photo with the network refused, a
    /// file that has moved, a volume that ran out of room.
    let failedIDs: [String]
    let bytes: Int64

    var isComplete: Bool { failedIDs.isEmpty }
    var exportedCount: Int { exportedIDs.count }
    var failedCount: Int { failedIDs.count }
}

enum ExportError: LocalizedError, Equatable {
    case noAccess
    case couldNotCreateFolder(String)
    case nothingExported
    case manifestNotWritten

    var errorDescription: String? {
        switch self {
        case .noAccess:
            return "That folder could not be opened, so nothing was written."
        case let .couldNotCreateFolder(message):
            return "The export folder could not be created: \(message)"
        case .nothingExported:
            return "None of the originals could be written, so nothing was exported. Nothing has been deleted."
        case .manifestNotWritten:
            return "The originals were written but the manifest beside them was not, so there would be no record of which copy each one was replaced by. The export was removed. Nothing has been deleted."
        }
    }
}

/// Writes the original bytes of everything about to be deleted, plus the manifest that says
/// what each one was and what stayed in its place.
protocol OriginalExporting: Sendable {
    func export(
        _ plan: [(item: MediaItem, entry: ExportManifest.Entry)],
        to destination: URL
    ) async throws -> ExportReceipt
}

/// The real one.
///
/// Originals, never renditions: a photo goes out as the resource PhotoKit calls the original,
/// so an export of an edited picture carries the bytes the camera wrote, and the paired movie
/// of a Live Photo goes with it. Nothing is downloaded from iCloud — an original that is not on
/// the device is reported as a failure rather than quietly costing the user their data
/// allowance, and a failure here stops the deletion rather than being swallowed.
final class FileSystemOriginalExporter: OriginalExporting {

    private let registry: any FolderRegistering

    init(registry: any FolderRegistering) {
        self.registry = registry
    }

    func export(
        _ plan: [(item: MediaItem, entry: ExportManifest.Entry)],
        to destination: URL
    ) async throws -> ExportReceipt {
        let registry = self.registry
        let folderName = Self.folderName(at: Date())

        // The picked folder is security-scoped and the scope has to be held across every write,
        // not taken per file.
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }

        let root = destination.appendingPathComponent(folderName, isDirectory: true)
        let originals = root.appendingPathComponent("originals", isDirectory: true)
        do {
            // `withIntermediateDirectories: false` on the root, deliberately: it makes an
            // existing folder an error instead of a silent merge. With `true` — and a folder
            // name that only went down to the minute — a second export into the same place
            // inside the same minute found every target filename already taken, refused every
            // write, concluded nothing had been exported, and deleted the directory holding
            // the *first* export's originals and manifest.
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        } catch {
            throw ExportError.couldNotCreateFolder(error.localizedDescription)
        }

        var exported: [String] = []
        var failed: [String] = []
        var bytes: Int64 = 0
        var written: [ExportManifest.Entry] = []

        for step in plan {
            let target = originals.appendingPathComponent(step.entry.exportedFileName)
            let companions: [String]?
            switch step.item.source {
            case .photoLibrary:
                companions = await Self.writeAsset(step.item, to: target)
            case .fileFolder:
                companions = await Self.writeFile(step.item, to: target, registry: registry) ? [] : nil
            }

            if let companions {
                exported.append(step.item.id)
                // The paired movie of a Live Photo used to be written and then not mentioned
                // anywhere: a file in the folder the manifest does not describe, which is the
                // inverse of the guarantee this document exists to make.
                written.append(step.entry.withCompanions(companions))
                bytes += step.item.totalByteSize
            } else {
                failed.append(step.item.id)
            }
        }

        guard !exported.isEmpty else {
            // Only ever the folder this call created, which is why the root is made with
            // `withIntermediateDirectories: false` above.
            try? FileManager.default.removeItem(at: root)
            throw ExportError.nothingExported
        }

        // Only what actually landed. A manifest listing a file that is not in the folder beside
        // it is the one thing that would make this feature worse than not having it.
        //
        // And it is not written with `try?`. The manifest is the only record of which copy each
        // original was being deleted in favour of — without it the folder is the pile of opaque
        // filenames this whole feature exists to avoid. A volume that fills on the last write
        // used to return a successful receipt saying "the folder holds the original bytes and a
        // manifest.json", on the strength of which the user then deleted the originals.
        let manifest = ExportManifest(createdAt: Date(), entries: written)
        do {
            let data = try manifest.encoded()
            try data.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw ExportError.manifestNotWritten
        }

        return ExportReceipt(
            folderName: folderName,
            exportedIDs: exported,
            failedIDs: failed,
            bytes: bytes
        )
    }

    /// Sortable, and readable by a person looking at a list of folders a year later.
    ///
    /// Down to the second. At minute resolution two exports a few taps apart collided, and the
    /// collision handling then destroyed the first one.
    static func folderName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "DupeSpace Export \(formatter.string(from: date))"
    }

    // MARK: - Photo library

    /// Returns the extra filenames written beside the primary one, or `nil` if nothing landed.
    private static func writeAsset(_ item: MediaItem, to target: URL) async -> [String]? {
        guard
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject
        else {
            return nil
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = primaryResource(in: resources) else { return nil }

        let options = PHAssetResourceRequestOptions()
        // Never over the network. An iCloud-only original is reported as a failure, which stops
        // the deletion — the alternative is an app that silently spends someone's data to make
        // a backup they did not know they were paying for.
        options.isNetworkAccessAllowed = false

        guard await write(primary, to: target, options: options) else { return nil }

        // A Live Photo is two files, and exporting only the still is exporting half of it.
        //
        // `-live.MOV` rather than swapping the extension: a video asset can carry a
        // `pairedVideo` resource too, and swapping `.MOV` for `.MOV` produced the same URL as
        // the primary — the existence guard then fired and the pair was silently dropped.
        guard
            let paired = resources.first(where: { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo })
        else {
            return []
        }

        let movieTarget = target
            .deletingLastPathComponent()
            .appendingPathComponent(target.deletingPathExtension().lastPathComponent + "-live.MOV")

        guard await write(paired, to: movieTarget, options: options) else { return [] }
        return [movieTarget.lastPathComponent]
    }

    /// The original, not a rendition. `.fullSizePhoto` is what the edits produced; `.photo` is
    /// what the camera wrote, and it is the one worth keeping.
    private static func primaryResource(in resources: [PHAssetResource]) -> PHAssetResource? {
        let order: [PHAssetResourceType] = [.photo, .video, .audio, .fullSizePhoto, .fullSizeVideo]
        for type in order {
            if let match = resources.first(where: { $0.type == type }) { return match }
        }
        return resources.first
    }

    private static func write(
        _ resource: PHAssetResource,
        to target: URL,
        options: PHAssetResourceRequestOptions
    ) async -> Bool {
        // Overwriting is not on the table: the filenames are unique by construction, and a
        // collision here would mean silently replacing something already in the folder.
        guard !FileManager.default.fileExists(atPath: target.path) else { return false }

        return await withCheckedContinuation { continuation in
            let resumeGuard = ResumeExportOnce()
            PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: options) { error in
                guard resumeGuard.claim() else { return }
                continuation.resume(returning: error == nil)
            }
        }
    }

    // MARK: - Granted folders

    private static func writeFile(
        _ item: MediaItem,
        to target: URL,
        registry: any FolderRegistering
    ) async -> Bool {
        let copied = FileMediaLibrary.withFile(itemID: item.id, registry: registry) { source -> Bool in
            guard !FileManager.default.fileExists(atPath: target.path) else { return false }

            var success = false
            var coordinationError: NSError?
            // Coordinated, for the same reason the deletion is: a folder in iCloud Drive has
            // other processes writing to it.
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                success = (try? FileManager.default.copyItem(at: readable, to: target)) != nil
            }
            return coordinationError == nil && success
        }
        return copied ?? false
    }
}

/// Writes nothing, reports everything as exported. For previews, UI tests and the simulator
/// walk, where there is no folder to pick and no PhotoKit asset behind the fixture ids.
final class StubOriginalExporter: OriginalExporting {

    func export(
        _ plan: [(item: MediaItem, entry: ExportManifest.Entry)],
        to _: URL
    ) async throws -> ExportReceipt {
        ExportReceipt(
            folderName: FileSystemOriginalExporter.folderName(at: Date()),
            exportedIDs: plan.map(\.item.id),
            failedIDs: [],
            bytes: plan.reduce(Int64(0)) { $0 + $1.item.totalByteSize }
        )
    }
}

private final class ResumeExportOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
