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

    private let library: MediaLibrary

    init(library: MediaLibrary) {
        self.library = library
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
        if access == .authorized {
            await loadInventory()
        }
    }

    func requestAccess() async {
        access = await library.requestAccess()
        if access == .authorized {
            await loadInventory()
        }
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
