import Combine
import Foundation
import DupeCore

@MainActor
final class OverviewViewModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var access: LibraryAccess = .notDetermined
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var storage: StorageSnapshot?
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var breakdown: [CategoryBreakdown] = []
    @Published private(set) var folders: [GrantedFolder] = []

    private let library: MediaLibrary
    private let folderRegistry: any FolderRegistering

    init(library: MediaLibrary, folderRegistry: any FolderRegistering = InMemoryFolderRegistry()) {
        self.library = library
        self.folderRegistry = folderRegistry
    }

    var libraryBytes: Int64 { InventoryAnalyzer.totalBytes(items) }
    var cloudOnlyBytes: Int64 { InventoryAnalyzer.cloudOnlyBytes(items) }
    var onDeviceLibraryBytes: Int64 { libraryBytes - cloudOnlyBytes }
    var largestItems: [MediaItem] { InventoryAnalyzer.largest(items, limit: 5) }

    var isLoading: Bool { state == .loading }

    var failureMessage: String? {
        if case let .failed(message) = state { return message }
        return nil
    }

    func refresh() async {
        storage = StorageProbe.current()
        access = library.currentAccess()
        folders = folderRegistry.folders()
        // Asked unconditionally: granted folders are readable whatever the photo library says.
        await loadInventory()
    }

    func requestAccess() async {
        access = await library.requestAccess()
        await loadInventory()
    }

    // MARK: - Folders

    func addFolder(at url: URL) async {
        guard let grant = FolderAccess.makeGrant(for: url) else { return }
        folderRegistry.add(grant)
        folders = folderRegistry.folders()
        await reloadInventory()
    }

    func removeFolder(id: UUID) async {
        folderRegistry.remove(id: id)
        folders = folderRegistry.folders()
        await reloadInventory()
    }

    private func reloadInventory() async {
        state = .idle
        await loadInventory()
    }

    private func loadInventory() async {
        guard state != .loading else { return }
        state = .loading
        do {
            let loaded = try await library.loadInventory()
            items = loaded
            breakdown = InventoryAnalyzer.breakdown(for: loaded)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
