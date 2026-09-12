import Foundation
import DupeCore

/// A folder the user has explicitly handed over.
///
/// iOS gives no app a view of the file system; it gives access to exactly what someone picks.
/// The bookmark is what keeps that grant alive across launches.
struct GrantedFolder: Identifiable, Hashable, Codable, Sendable {

    let id: UUID
    var displayName: String
    var bookmark: Data

    init(id: UUID = UUID(), displayName: String, bookmark: Data) {
        self.id = id
        self.displayName = displayName
        self.bookmark = bookmark
    }
}

protocol FolderRegistering: Sendable {
    func folders() -> [GrantedFolder]
    func add(_ folder: GrantedFolder)
    func remove(id: UUID)
    /// Replaces the stored bookmark for a grant, keeping its id and name.
    ///
    /// A bookmark goes stale when the folder moves, when the volume changes, or after a
    /// restore. It keeps resolving for a while and then stops, and when it stops the grant
    /// fails silently: the folder yields no items, contributes nothing to the inventory, and
    /// says nothing about it. `URL(resolvingBookmarkData:)` reports staleness and the fix is to
    /// write a fresh bookmark back while the security scope is still held.
    func refreshBookmark(id: UUID, to bookmark: Data)
}

/// Identifies a file by the grant it came from plus its path inside that grant.
///
/// Not by absolute path: the container directory changes between installs, and a stale
/// absolute path is the sort of thing that makes a deletion land somewhere unintended.
enum FileItemID {

    private static let prefix = "file:"
    private static let separator: Character = "|"

    static func make(folderID: UUID, relativePath: String) -> String {
        "\(prefix)\(folderID.uuidString)\(separator)\(relativePath)"
    }

    static func parse(_ id: String) -> (folderID: UUID, relativePath: String)? {
        guard id.hasPrefix(prefix) else { return nil }
        let body = id.dropFirst(prefix.count)
        guard let separatorIndex = body.firstIndex(of: separator) else { return nil }

        let uuidPart = String(body[body.startIndex..<separatorIndex])
        let path = String(body[body.index(after: separatorIndex)...])
        guard let folderID = UUID(uuidString: uuidPart), !path.isEmpty else { return nil }
        return (folderID, path)
    }

    static func isFile(_ id: String) -> Bool { id.hasPrefix(prefix) }
}

/// Keeps grants in user defaults. Small, and exactly as durable as the app itself.
final class UserDefaultsFolderRegistry: FolderRegistering, @unchecked Sendable {

    private static let key = "DupeSpace.grantedFolders"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func folders() -> [GrantedFolder] {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([GrantedFolder].self, from: data)) ?? []
    }

    func add(_ folder: GrantedFolder) {
        lock.lock(); defer { lock.unlock() }
        var current = decodeLocked()
        current.removeAll { $0.bookmark == folder.bookmark }
        current.append(folder)
        writeLocked(current)
    }

    func remove(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var current = decodeLocked()
        current.removeAll { $0.id == id }
        writeLocked(current)
    }

    func refreshBookmark(id: UUID, to bookmark: Data) {
        lock.lock(); defer { lock.unlock() }
        var current = decodeLocked()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index].bookmark = bookmark
        writeLocked(current)
    }

    private func decodeLocked() -> [GrantedFolder] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([GrantedFolder].self, from: data)) ?? []
    }

    private func writeLocked(_ folders: [GrantedFolder]) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

final class InMemoryFolderRegistry: FolderRegistering, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [GrantedFolder]

    init(folders: [GrantedFolder] = []) {
        storage = folders
    }

    func folders() -> [GrantedFolder] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func add(_ folder: GrantedFolder) {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll { $0.bookmark == folder.bookmark }
        storage.append(folder)
    }

    func remove(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll { $0.id == id }
    }

    func refreshBookmark(id: UUID, to bookmark: Data) {
        lock.lock(); defer { lock.unlock() }
        guard let index = storage.firstIndex(where: { $0.id == id }) else { return }
        storage[index].bookmark = bookmark
    }
}

/// Resolves a grant back into a usable URL and holds the security scope while you work.
enum FolderAccess {

    /// Runs `body` with the folder's URL. Returns `nil` when the grant can no longer be
    /// resolved — a folder the user moved or deleted is simply gone, not an error worth
    /// interrupting them over.
    static func withFolder<T>(
        _ folder: GrantedFolder,
        renewingWith registry: (any FolderRegistering)? = nil,
        _ body: (URL) throws -> T
    ) rethrows -> T? {
        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: folder.bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else {
            return nil
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        renew(folder, at: url, isStale: isStale, registry: registry)

        return try body(url)
    }

    /// Writes a fresh bookmark back when the old one is on its way out.
    ///
    /// `isStale` used to be declared, passed by reference and then never read — in both
    /// resolvers. A stale bookmark still resolves, right up until the day it does not, and on
    /// that day the grant disappears without a word: the folder enumerates empty, its files
    /// leave the inventory, and the overlap check that stops the same file being indexed twice
    /// stops seeing it. The renewal has to happen inside the security scope, which is why it
    /// lives here rather than at the call site.
    private static func renew(
        _ folder: GrantedFolder,
        at url: URL,
        isStale: Bool,
        registry: (any FolderRegistering)?
    ) {
        guard isStale, let registry, let fresh = try? url.bookmarkData() else { return }
        registry.refreshBookmark(id: folder.id, to: fresh)
    }

    /// The same, for work that has to await inside the grant. The security scope has to stay
    /// held for the whole read, and AVFoundation does not read synchronously.
    static func withFolderAsync<T>(
        _ folder: GrantedFolder,
        renewingWith registry: (any FolderRegistering)? = nil,
        _ body: (URL) async -> T
    ) async -> T? {
        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: folder.bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else {
            return nil
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        renew(folder, at: url, isStale: isStale, registry: registry)

        return await body(url)
    }

    static func resolvedPath(for folder: GrantedFolder) -> String? {
        withFolder(folder) { $0.standardizedFileURL.path }
    }

    /// True when one path contains the other, or they are the same folder.
    ///
    /// Granting a folder and then something inside it would index one physical file twice, and
    /// the engine would be right to call the two entries identical — at which point deleting
    /// the loser deletes the survivor's own file, with nothing to restore it from.
    static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.hasSuffix("/") ? lhs : lhs + "/"
        let right = rhs.hasSuffix("/") ? rhs : rhs + "/"
        return left.hasPrefix(right) || right.hasPrefix(left)
    }

    static func makeGrant(for url: URL) -> GrantedFolder? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let bookmark = try? url.bookmarkData() else { return nil }
        return GrantedFolder(displayName: url.lastPathComponent, bookmark: bookmark)
    }
}
