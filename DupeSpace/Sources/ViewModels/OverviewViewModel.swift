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
    /// Why the last folder someone picked was not taken. Cleared as soon as one is.
    @Published private(set) var folderMessage: String?

    private let library: MediaLibrary
    private let folderRegistry: any FolderRegistering
    private let changeObserver: (any LibraryChangeObserving)?

    /// Guards the enumeration itself. `state` drives the UI and is the wrong thing to gate on:
    /// resetting it to re-read defeated the guard and let several full library reads run at
    /// once, with the last — possibly oldest — result winning.
    private var isEnumerating = false
    private var reloadRequested = false

    init(
        library: MediaLibrary,
        folderRegistry: any FolderRegistering = InMemoryFolderRegistry(),
        changeObserver: (any LibraryChangeObserving)? = nil
    ) {
        self.library = library
        self.folderRegistry = folderRegistry
        self.changeObserver = changeObserver
    }

    // Computed once when the inventory lands, not on every read.
    //
    // These were four computed properties over `items`, and the overview screen reads them
    // several times per body pass — `largestItems` alone sorted all fifty thousand items to
    // take five, twice per render, on the main actor. Nothing about them changes between
    // inventory loads, so they are stored.
    @Published private(set) var libraryBytes: Int64 = 0
    @Published private(set) var cloudOnlyBytes: Int64 = 0
    @Published private(set) var largestItems: [MediaItem] = []

    var onDeviceLibraryBytes: Int64 { libraryBytes - cloudOnlyBytes }

    var isLoading: Bool { state == .loading }

    var failureMessage: String? {
        if case let .failed(message) = state { return message }
        return nil
    }

    /// Starts watching the library so the numbers on screen keep describing the library that
    /// actually exists — deleting photos in Photos should not leave a stale total here.
    func beginObservingLibrary() {
        guard let changeObserver else { return }
        changeObserver.startObserving { [weak self] in
            Task { await self?.reloadAfterExternalChange() }
        }
    }

    func stopObservingLibrary() {
        changeObserver?.stopObserving()
    }

    private func reloadAfterExternalChange() async {
        await loadInventory(force: true)
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
        guard let grant = FolderAccess.makeGrant(for: url) else {
            folderMessage = "That folder could not be read."
            return
        }

        let candidate = url.standardizedFileURL.path
        for existing in folderRegistry.folders() {
            guard let existingPath = FolderAccess.resolvedPath(for: existing) else { continue }
            guard FolderAccess.overlaps(candidate, existingPath) else { continue }

            folderMessage = "\(existing.displayName) already covers that folder. Indexing one file through two grants would make it look like its own duplicate."
            return
        }

        folderMessage = nil
        folderRegistry.add(grant)
        folders = folderRegistry.folders()
        await reloadInventory()
    }

    func removeFolder(id: UUID) async {
        folderMessage = nil
        folderRegistry.remove(id: id)
        folders = folderRegistry.folders()
        await reloadInventory()
    }

    private func reloadInventory() async {
        await loadInventory(force: true)
    }

    private func loadInventory(force: Bool = false) async {
        // A change that arrives mid-read queues exactly one more read rather than racing the
        // one in flight.
        if isEnumerating {
            if force { reloadRequested = true }
            return
        }

        isEnumerating = true
        defer { isEnumerating = false }

        repeat {
            reloadRequested = false
            state = .loading
            do {
                let loaded = try await library.loadInventory()
                items = loaded
                breakdown = InventoryAnalyzer.breakdown(for: loaded)
                libraryBytes = InventoryAnalyzer.totalBytes(loaded)
                cloudOnlyBytes = InventoryAnalyzer.cloudOnlyBytes(loaded)
                largestItems = InventoryAnalyzer.largest(loaded, limit: 5)
                state = .loaded
                WidgetPublisher.publish(storage: storage, libraryBytes: onDeviceLibraryBytes)
            } catch {
                state = .failed(error.localizedDescription)
            }
        } while reloadRequested
    }
}
