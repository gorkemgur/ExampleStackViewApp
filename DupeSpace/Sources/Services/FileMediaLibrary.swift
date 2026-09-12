import Foundation
import ImageIO
import UniformTypeIdentifiers
import DupeCore

/// Reads the folders the user has granted.
///
/// There is no permission prompt here: on iOS a folder is either handed over or it is not, so
/// access is always "authorized" and simply covers nothing until someone picks a folder.
final class FileMediaLibrary: MediaLibrary {

    private let registry: any FolderRegistering

    init(registry: any FolderRegistering) {
        self.registry = registry
    }

    func currentAccess() -> LibraryAccess { .authorized }

    func requestAccess() async -> LibraryAccess { .authorized }

    func loadInventory() async throws -> [MediaItem] {
        let registry = self.registry
        let folders = registry.folders()
        guard !folders.isEmpty else { return [] }

        return await Task.detached(priority: .userInitiated) {
            folders.flatMap { Self.items(in: $0, registry: registry) }
        }.value
    }

    // MARK: - Enumeration

    /// The registry is passed in rather than read off `self`: this runs on a detached task and
    /// is where a stale bookmark gets written back, so it needs the store, not the instance.
    static func items(in folder: GrantedFolder, registry: (any FolderRegistering)? = nil) -> [MediaItem] {
        FolderAccess.withFolder(folder, renewingWith: registry) { root -> [MediaItem] in
            let keys: [URLResourceKey] = [
                .isRegularFileKey,
                .fileSizeKey,
                .contentTypeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ]

            guard
                let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            else {
                return []
            }

            var found: [MediaItem] = []
            for case let url as URL in enumerator {
                guard let item = makeItem(url: url, root: root, folder: folder, keys: keys) else {
                    continue
                }
                found.append(item)
            }
            return found.sorted { $0.id < $1.id }
        } ?? []
    }

    private static func makeItem(
        url: URL,
        root: URL,
        folder: GrantedFolder,
        keys: [URLResourceKey]
    ) -> MediaItem? {

        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        guard values.isRegularFile == true else { return nil }

        let bytes = Int64(values.fileSize ?? 0)
        guard bytes > 0 else { return nil }

        // An iCloud file that has not been downloaded has no bytes here to read, and reaching
        // for them would mean a download. Reported as not local, exactly like a photo whose
        // original lives in iCloud.
        let isPlaceholder = values.isUbiquitousItem == true
            && values.ubiquitousItemDownloadingStatus != .current

        let relativePath = Self.relativePath(of: url, under: root)
        guard !relativePath.isEmpty else { return nil }

        let type = values.contentType
        let kind: MediaKind
        if type?.conforms(to: .image) == true {
            kind = .image
        } else if type?.conforms(to: .movie) == true || type?.conforms(to: .audiovisualContent) == true {
            kind = .video
        } else {
            kind = .document
        }

        // Dimensions, without decoding the image.
        //
        // These were never filled in for files, and the consequences reached further than a
        // blank field. `sameFraming` compares aspect ratios, so with both sides at zero it
        // returned false for every file pair — which meant a file image could never be labelled
        // `.nearExact` no matter how identical, `CleanupPlanner`'s "the keeper has more pixels"
        // rule could never be true for one, and every duplicate in a granted folder landed in
        // `.similar` and was never pre-selected. The near-duplicate tier was switched off for
        // half the app's sources, quietly, by an unset field.
        let pixels = kind == .image ? Self.pixelSize(of: url) : (width: 0, height: 0)

        return MediaItem(
            id: FileItemID.make(folderID: folder.id, relativePath: relativePath),
            source: .fileFolder,
            kind: kind,
            displayName: url.lastPathComponent,
            byteSize: bytes,
            pixelWidth: pixels.width,
            pixelHeight: pixels.height,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            isLocallyAvailable: !isPlaceholder,
            isUserLibraryOriginal: false
        )
    }

    /// The image's dimensions, read from its header.
    ///
    /// `CGImageSourceCopyPropertiesAtIndex` reads the metadata block and stops; it does not
    /// decode pixels, so this costs about what the `stat` beside it costs.
    static func pixelSize(of url: URL) -> (width: Int, height: Int) {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return (0, 0)
        }
        return (width, height)
    }

    /// Path of `url` relative to `root`, with no leading slash.
    static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path

        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        let suffix = filePath.dropFirst(rootPath.count)
        return String(suffix.drop(while: { $0 == "/" }))
    }

    /// Resolves an item id back to a file on disk, holding the grant while `body` runs.
    static func withFile<T>(
        itemID: String,
        registry: any FolderRegistering,
        _ body: (URL) throws -> T
    ) rethrows -> T? {
        guard
            let parsed = FileItemID.parse(itemID),
            let folder = registry.folders().first(where: { $0.id == parsed.folderID })
        else {
            return nil
        }

        // The nested optional is flattened: "the grant would not resolve" and "the path was
        // not inside it" are the same answer to the caller — there is no file here for you.
        let resolved: T?? = try FolderAccess.withFolder(folder, renewingWith: registry) { root -> T? in
            let target = root.appendingPathComponent(parsed.relativePath).standardizedFileURL

            // The relative path comes from this app's own enumeration, but it is also written
            // to disk in the cache and the history and read back later. Before a deletion the
            // cheap check is worth making: a path that resolves outside the folder the user
            // granted is not a file this app may touch, whatever produced it.
            guard target.path.hasPrefix(root.standardizedFileURL.path + "/") else { return nil }

            return try body(target)
        }
        return resolved ?? nil
    }

    /// The same guard, for work that has to await.
    ///
    /// `videoSignature` used to build its URL by hand — `root.appendingPathComponent(...)` with
    /// no containment check — because the synchronous helper could not carry an `async` body.
    /// It only ever reads, so it could not have deleted outside the grant, but it could read
    /// outside it, and the reason the check exists is that the relative path is written to disk
    /// and read back later.
    static func withFileAsync<T>(
        itemID: String,
        registry: any FolderRegistering,
        _ body: @Sendable (URL) async -> T?
    ) async -> T? {
        guard
            let parsed = FileItemID.parse(itemID),
            let folder = registry.folders().first(where: { $0.id == parsed.folderID })
        else {
            return nil
        }

        let resolved: T?? = await FolderAccess.withFolderAsync(folder, renewingWith: registry) { root -> T? in
            let target = root.appendingPathComponent(parsed.relativePath).standardizedFileURL
            guard target.path.hasPrefix(root.standardizedFileURL.path + "/") else { return nil }
            return await body(target)
        }
        return resolved ?? nil
    }
}
