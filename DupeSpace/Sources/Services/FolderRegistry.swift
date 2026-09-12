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
}

/// Resolves a grant back into a usable URL and holds the security scope while you work.
enum FolderAccess {

    /// Runs `body` with the folder's URL. Returns `nil` when the grant can no longer be
    /// resolved — a folder the user moved or deleted is simply gone, not an error worth
    /// interrupting them over.
    static func withFolder<T>(_ folder: GrantedFolder, _ body: (URL) throws -> T) rethrows -> T? {
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

        return try body(url)
    }

    static func makeGrant(for url: URL) -> GrantedFolder? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let bookmark = try? url.bookmarkData() else { return nil }
        return GrantedFolder(displayName: url.lastPathComponent, bookmark: bookmark)
    }
}
