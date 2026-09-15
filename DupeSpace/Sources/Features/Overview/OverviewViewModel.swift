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
    /// What the library carries that nobody can remove. See `SecondResources`.
    @Published private(set) var secondResources = SecondResources()
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

    /// Whether the screen has asked for the library to be watched, as opposed to whether it
    /// is being watched. The screen asks once, at launch, when the permission is usually still
    /// unanswered — so the request has to outlive the moment it could not be honoured.
    private var wantsObservation = false
    private var isObserving = false

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
        wantsObservation = true
        startObservingIfReadable()
    }

    func stopObservingLibrary() {
        wantsObservation = false
        guard isObserving else { return }
        isObserving = false
        changeObserver?.stopObserving()
    }

    /// Registers only once the library can actually be read.
    ///
    /// `PHPhotoLibrary.shared().register(_:)` is not a passive subscription — it is a PhotoKit
    /// call, and on a real device it was what put the permission alert on screen at launch,
    /// before anybody had read the card that explains what the app wants and promises nothing
    /// leaves the phone. Worse, the grant then arrived through a route that writes nothing to
    /// `access`, so the wall stayed up over a library the app was by then allowed to read.
    ///
    /// Asking is now something only the card's button does. This waits for the answer.
    private func startObservingIfReadable() {
        guard wantsObservation, !isObserving, access == .authorized else { return }
        guard let changeObserver else { return }
        isObserving = true
        changeObserver.startObserving { [weak self] in
            Task { await self?.reloadAfterExternalChange() }
        }
    }

    private func reloadAfterExternalChange() async {
        await loadInventory(force: true)
    }

    func refresh() async {
        storage = StorageProbe.current()
        access = library.currentAccess()
        folders = folderRegistry.folders()
        startObservingIfReadable()
        // Asked unconditionally: granted folders are readable whatever the photo library says.
        await loadInventory()
    }

    /// Answers the permission, and decides whether the caller waits for the library behind it.
    ///
    /// Waiting is the default, because it is what the access card wants: that card sits on a
    /// screen which draws a loading card underneath it, so the read is visible while it happens.
    ///
    /// The onboarding cover wants the opposite, and that is the whole of this parameter. Its key
    /// is disabled while the grant is in flight and the screen dismisses only once the grant
    /// returns — so awaiting the inventory here held the cover up for as long as it took to
    /// enumerate the library, with nothing on screen moving and the key dead. On a real phone
    /// that is the "granting photo access strands you on the onboarding screen" report.
    ///
    /// `access` is already correct on the line above, which is what makes this safe: the screen
    /// behind the cover is right the moment it is uncovered, and the enumeration is work it can
    /// do in its own time.
    func requestAccess(waitingForInventory: Bool = true) async {
        access = await library.requestAccess()
        startObservingIfReadable()
        guard waitingForInventory else {
            Task { await loadInventory() }
            return
        }
        await loadInventory()
    }

    /// Re-reads the permission, and reads the library again only if it changed.
    ///
    /// The permission is not the app's to hold. It can be answered in a system alert the app
    /// did not raise, turned on in Settings — which is where this very screen's second button
    /// sends people — or taken away while the app sits in the background. Every one of those
    /// happens with `access` already read and nothing left to read it again, which on a real
    /// phone meant a permission wall standing over a library the app was allowed to open.
    ///
    /// It runs every time the app comes to the front, so the early return is not a nicety.
    /// Re-enumerating on each return would charge fifty thousand assets to answering a phone
    /// call, and this app is *for* libraries that size.
    func refreshAccess() async {
        let current = library.currentAccess()
        guard current != access else { return }

        access = current
        startObservingIfReadable()
        // Both directions: a grant makes a library readable, and a revocation must take its
        // totals off the screen rather than leave them describing what can no longer be read.
        await loadInventory(force: true)
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
                // Summarised where the enumeration already is — off the main actor. See the
                // note on `InventorySummary`.
                let summary = await Task.detached(priority: .userInitiated) {
                    InventorySummary.of(loaded)
                }.value
                apply(summary)
                state = .loaded
                WidgetPublisher.publish(storage: storage, libraryBytes: onDeviceLibraryBytes)
            } catch {
                state = .failed(error.localizedDescription)
            }
        } while reloadRequested
    }

    /// Six writes, back to back, with nothing between them that can suspend.
    ///
    /// That is the whole requirement: `@Published` writes separated by an `await` — or by an
    /// O(n) pass, which is what used to separate these — let the main actor service a redraw in
    /// the gap, so one library load could invalidate the overview six times. Synchronous and
    /// adjacent, they coalesce into one update.
    private func apply(_ summary: InventorySummary) {
        items = summary.items
        breakdown = summary.breakdown
        secondResources = summary.secondResources
        libraryBytes = summary.libraryBytes
        cloudOnlyBytes = summary.cloudOnlyBytes
        largestItems = summary.largestItems
    }
}

/// Everything the overview reads about an inventory, worked out in one place.
///
/// This used to be six statements in `loadInventory`, each assigning a `@Published` property on
/// the main actor. `breakdown`, `tally`, `totalBytes` and `cloudOnlyBytes` each walk the whole
/// inventory and `largest` sorts it — five linear passes and one `n log n`, over as many as
/// fifty thousand items, on the actor the app needs in order to draw anything at all, at exactly
/// the moment it is trying to draw its first screen.
///
/// The enumeration itself was already off the main actor (`PhotoKitMediaLibrary.loadInventory`
/// runs in a detached task); only the arithmetic after it was not. Now both are, and the result
/// crosses back as one `Sendable` value.
struct InventorySummary: Sendable {

    var items: [MediaItem] = []
    var breakdown: [CategoryBreakdown] = []
    var secondResources = SecondResources()
    var libraryBytes: Int64 = 0
    var cloudOnlyBytes: Int64 = 0
    var largestItems: [MediaItem] = []

    static func of(_ items: [MediaItem]) -> InventorySummary {
        InventorySummary(
            items: items,
            breakdown: InventoryAnalyzer.breakdown(for: items),
            secondResources: SecondResources.tally(items),
            libraryBytes: InventoryAnalyzer.totalBytes(items),
            cloudOnlyBytes: InventoryAnalyzer.cloudOnlyBytes(items),
            largestItems: InventoryAnalyzer.largest(items, limit: 5)
        )
    }
}
