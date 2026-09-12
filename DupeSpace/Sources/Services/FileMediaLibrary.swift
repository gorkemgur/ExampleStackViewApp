import Foundation
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
        let folders = registry.folders()
        guard !folders.isEmpty else { return [] }

        return await Task.detached(priority: .userInitiated) {
            folders.flatMap { Self.items(in: $0) }
        }.value
    }

    // MARK: - Enumeration

    static func items(in folder: GrantedFolder) -> [MediaItem] {
        FolderAccess.withFolder(folder) { root -> [MediaItem] in
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

        return MediaItem(
            id: FileItemID.make(folderID: folder.id, relativePath: relativePath),
            source: .fileFolder,
            kind: kind,
            displayName: url.lastPathComponent,
            byteSize: bytes,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            isLocallyAvailable: !isPlaceholder,
            isUserLibraryOriginal: false
        )
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
        let resolved: T?? = try FolderAccess.withFolder(folder) { root -> T? in
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
}
