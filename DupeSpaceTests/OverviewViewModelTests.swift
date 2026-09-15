import XCTest
import DupeCore
@testable import DupeSpace

@MainActor
final class OverviewViewModelTests: XCTestCase {

    func testAuthorisedLibraryLoadsAndSummarises() async {
        let model = OverviewViewModel(library: StubMediaLibrary.previewFixture())
        await model.refresh()

        XCTAssertEqual(model.access, .authorized)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertFalse(model.items.isEmpty)
        XCTAssertFalse(model.breakdown.isEmpty)
        XCTAssertEqual(model.libraryBytes, InventoryAnalyzer.totalBytes(model.items))
    }

    func testUnauthorisedLibraryYieldsNothing() async {
        let model = OverviewViewModel(library: StubMediaLibrary(access: .denied, items: StubMediaLibrary.sampleItems()))
        await model.refresh()

        XCTAssertEqual(model.access, .denied)
        XCTAssertTrue(model.items.isEmpty, "nothing may be read without permission")
        XCTAssertTrue(model.breakdown.isEmpty)
    }

    func testLimitedAccessIsTreatedAsNotUsable() async {
        let model = OverviewViewModel(library: StubMediaLibrary(access: .limited, items: StubMediaLibrary.sampleItems()))
        await model.refresh()

        XCTAssertEqual(model.access, .limited)
        XCTAssertTrue(model.items.isEmpty)
    }

    func testGrantedFoldersAreSurfaced() async {
        let registry = InMemoryFolderRegistry(folders: [
            GrantedFolder(displayName: "Downloads", bookmark: Data([1]))
        ])
        let model = OverviewViewModel(
            library: StubMediaLibrary.previewFixture(),
            folderRegistry: registry
        )
        await model.refresh()

        XCTAssertEqual(model.folders.map(\.displayName), ["Downloads"])

        await model.removeFolder(id: registry.folders()[0].id)
        XCTAssertTrue(model.folders.isEmpty)
    }

    func testRequestingAccessLoadsTheLibrary() async {
        let model = OverviewViewModel(library: StubMediaLibrary.previewFixture())
        await model.requestAccess()

        XCTAssertEqual(model.access, .authorized)
        XCTAssertFalse(model.items.isEmpty)
    }

    func testCloudOnlyBytesAreSeparatedFromOnDeviceBytes() async {
        let model = OverviewViewModel(library: StubMediaLibrary.previewFixture())
        await model.refresh()

        XCTAssertGreaterThan(model.cloudOnlyBytes, 0, "the fixture includes a cloud-only original")
        XCTAssertEqual(model.onDeviceLibraryBytes, model.libraryBytes - model.cloudOnlyBytes)
    }

    func testAChangeInTheLibraryRefreshesWhatIsOnScreen() async {
        let library = MutableLibrary(items: [
            MediaItem(id: "a", source: .photoLibrary, kind: .image, byteSize: 10)
        ])
        let observer = StubLibraryChangeObserver()
        let model = OverviewViewModel(library: library, changeObserver: observer)

        await model.refresh()
        XCTAssertEqual(model.items.count, 1)

        model.beginObservingLibrary()
        XCTAssertTrue(observer.isObserving)

        library.replace(with: [
            MediaItem(id: "a", source: .photoLibrary, kind: .image, byteSize: 10),
            MediaItem(id: "b", source: .photoLibrary, kind: .video, byteSize: 20)
        ])
        observer.simulateChange()

        let deadline = Date().addingTimeInterval(5)
        while model.items.count < 2 && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(model.items.count, 2, "stale numbers are the one thing this app must not show")
        XCTAssertEqual(model.libraryBytes, 30)
    }

    func testNothingIsWatchedUntilItIsAskedFor() async {
        let observer = StubLibraryChangeObserver()
        let model = OverviewViewModel(library: StubMediaLibrary.previewFixture(), changeObserver: observer)

        await model.refresh()
        XCTAssertFalse(observer.isObserving)

        model.beginObservingLibrary()
        XCTAssertTrue(observer.isObserving)

        model.stopObservingLibrary()
        XCTAssertFalse(observer.isObserving)
    }

    func testFailureIsSurfacedRatherThanSwallowed() async {
        let model = OverviewViewModel(library: FailingLibrary())
        await model.refresh()

        XCTAssertNotNil(model.failureMessage)
        XCTAssertTrue(model.items.isEmpty)
    }

    // MARK: - A permission answered somewhere this app was not looking

    /// The bug the first run on a real phone found, and the reason it is written as a test.
    ///
    /// On the device the system's permission alert appeared at launch — not from the card's
    /// button — and the user allowed it. The wall stayed up anyway, because `access` is written
    /// in exactly two places: `refresh()`, which had already run, and `requestAccess()`, which
    /// only the card's button reaches. A grant that arrives by any other route left the screen
    /// describing a permission state that had stopped being true, until the app was relaunched.
    ///
    /// Two other routes lead here and neither is exotic: Settings — which the card's own second
    /// button sends people to — and a permission revoked while the app sat in the background.
    func testAGrantMadeOutsideTheAppIsNoticedWhenItComesBack() async {
        let library = GrantedElsewhereLibrary(
            items: [MediaItem(id: "a", source: .photoLibrary, kind: .image, byteSize: 10)]
        )
        let model = OverviewViewModel(library: library)

        await model.refresh()
        XCTAssertEqual(model.access, .notDetermined)
        XCTAssertTrue(model.items.isEmpty)

        // The system alert, answered. Nothing in the app asked for it, so nothing in the app
        // is told about it.
        library.grantFromOutsideTheApp()

        await model.refreshAccess()

        XCTAssertEqual(
            model.access, .authorized,
            "the permission wall stayed on screen after the permission was given"
        )
        XCTAssertFalse(model.items.isEmpty, "authorised and still showing nothing")
    }

    /// A permission taken away while the app was in the background has to land too, or the
    /// screen goes on totalling a library it can no longer read.
    func testAPermissionTakenAwayWhileAwayIsNoticedToo() async {
        let library = GrantedElsewhereLibrary(
            status: .authorized,
            items: [MediaItem(id: "a", source: .photoLibrary, kind: .image, byteSize: 10)]
        )
        let model = OverviewViewModel(library: library)

        await model.refresh()
        XCTAssertFalse(model.items.isEmpty)

        library.revokeFromOutsideTheApp()
        await model.refreshAccess()

        XCTAssertEqual(model.access, .denied)
        XCTAssertTrue(model.items.isEmpty, "items outlived the permission that allowed reading them")
    }

    /// The check runs every time the app comes to the front, so it has to be cheap.
    ///
    /// Re-enumerating on every app switch would make the fix worse than the bug on the library
    /// this app is for: fifty thousand assets, read again because somebody answered a phone
    /// call. Nothing changed means nothing is read.
    func testComingBackWithTheSamePermissionReadsNothingAgain() async {
        let library = GrantedElsewhereLibrary(
            status: .authorized,
            items: [MediaItem(id: "a", source: .photoLibrary, kind: .image, byteSize: 10)]
        )
        let model = OverviewViewModel(library: library)

        await model.refresh()
        let readsAfterFirstLoad = library.loadCount

        await model.refreshAccess()
        await model.refreshAccess()
        await model.refreshAccess()

        XCTAssertEqual(
            library.loadCount, readsAfterFirstLoad,
            "an unchanged permission re-read the whole library, three times"
        )
    }

    /// Registering a change observer is a PhotoKit call, and on a device it is what put an
    /// unexplained permission alert on the screen before anybody had read the card that
    /// explains what the app wants. Nothing is registered until the library is readable.
    func testTheLibraryIsNotWatchedWhileThePermissionIsUnanswered() async {
        let library = GrantedElsewhereLibrary(
            items: [MediaItem(id: "a", source: .photoLibrary, kind: .image, byteSize: 10)]
        )
        let observer = StubLibraryChangeObserver()
        let model = OverviewViewModel(library: library, changeObserver: observer)

        await model.refresh()
        model.beginObservingLibrary()

        XCTAssertFalse(
            observer.isObserving,
            "watching an unreadable library is what asks PhotoKit for permission out of turn"
        )

        library.grantFromOutsideTheApp()
        await model.refreshAccess()

        XCTAssertTrue(
            observer.isObserving,
            "the request was made and the library became readable, so watching must start"
        )
    }

    /// And the request has to be remembered rather than re-asked: the screen calls
    /// `beginObservingLibrary()` once, at launch, when the answer is usually still unknown.
    func testObservationIsNotStartedIfItWasNeverAskedFor() async {
        let library = GrantedElsewhereLibrary(
            items: [MediaItem(id: "a", source: .photoLibrary, kind: .image, byteSize: 10)]
        )
        let observer = StubLibraryChangeObserver()
        let model = OverviewViewModel(library: library, changeObserver: observer)

        await model.refresh()
        library.grantFromOutsideTheApp()
        await model.refreshAccess()

        XCTAssertFalse(observer.isObserving, "nobody asked for this")
    }

    /// Tapping the card's button is the route that always worked. It has to keep working, and
    /// it has to start the watching the launch could not.
    func testTheCardsOwnButtonStartsWatchingOnceItSucceeds() async {
        let library = GrantedElsewhereLibrary(
            items: [MediaItem(id: "a", source: .photoLibrary, kind: .image, byteSize: 10)]
        )
        let observer = StubLibraryChangeObserver()
        let model = OverviewViewModel(library: library, changeObserver: observer)

        await model.refresh()
        model.beginObservingLibrary()
        XCTAssertFalse(observer.isObserving)

        await model.requestAccess()

        XCTAssertEqual(model.access, .authorized)
        XCTAssertFalse(model.items.isEmpty)
        XCTAssertTrue(observer.isObserving)
    }
}

/// A library whose permission changes without the app having asked — the phone's own alert,
/// the Settings app, a policy. `requestAccess()` is deliberately *not* the only way to become
/// authorised here, because on a real device it is not.
private final class GrantedElsewhereLibrary: MediaLibrary, @unchecked Sendable {

    private let lock = NSLock()
    private var status: LibraryAccess
    private var _loadCount = 0
    private let items: [MediaItem]

    init(status: LibraryAccess = .notDetermined, items: [MediaItem]) {
        self.status = status
        self.items = items
    }

    var loadCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _loadCount
    }

    func grantFromOutsideTheApp() {
        lock.lock(); status = .authorized; lock.unlock()
    }

    func revokeFromOutsideTheApp() {
        lock.lock(); status = .denied; lock.unlock()
    }

    func currentAccess() -> LibraryAccess {
        lock.lock(); defer { lock.unlock() }
        return status
    }

    func requestAccess() async -> LibraryAccess {
        lock.lock(); status = .authorized; lock.unlock()
        return .authorized
    }

    func loadInventory() async throws -> [MediaItem] {
        lock.lock()
        _loadCount += 1
        let readable = status == .authorized
        let items = self.items
        lock.unlock()
        return readable ? items : []
    }
}

/// A library whose contents can change between reads, which is what makes "did it actually
/// reload" an assertion rather than a guess.
private final class MutableLibrary: MediaLibrary, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [MediaItem]
    private var _loadCount = 0

    init(items: [MediaItem]) { storage = items }

    var loadCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _loadCount
    }

    func replace(with items: [MediaItem]) {
        lock.lock(); storage = items; lock.unlock()
    }

    func currentAccess() -> LibraryAccess { .authorized }
    func requestAccess() async -> LibraryAccess { .authorized }

    func loadInventory() async throws -> [MediaItem] {
        lock.lock()
        _loadCount += 1
        let items = storage
        lock.unlock()
        return items
    }
}

private struct LibraryError: LocalizedError {
    var errorDescription: String? { "library unavailable" }
}

private final class FailingLibrary: MediaLibrary {
    func currentAccess() -> LibraryAccess { .authorized }
    func requestAccess() async -> LibraryAccess { .authorized }
    func loadInventory() async throws -> [MediaItem] { throw LibraryError() }
}
