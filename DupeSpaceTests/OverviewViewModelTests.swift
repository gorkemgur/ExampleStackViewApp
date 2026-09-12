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
