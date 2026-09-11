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

    func testUnauthorisedLibraryIsNeverRead() async {
        let model = OverviewViewModel(library: StubMediaLibrary(access: .denied, items: StubMediaLibrary.sampleItems()))
        await model.refresh()

        XCTAssertEqual(model.access, .denied)
        XCTAssertTrue(model.items.isEmpty, "nothing may be read without permission")
        XCTAssertEqual(model.state, .idle)
    }

    func testLimitedAccessIsTreatedAsNotUsable() async {
        let model = OverviewViewModel(library: StubMediaLibrary(access: .limited, items: StubMediaLibrary.sampleItems()))
        await model.refresh()

        XCTAssertEqual(model.access, .limited)
        XCTAssertTrue(model.items.isEmpty)
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

    func testFailureIsSurfacedRatherThanSwallowed() async {
        let model = OverviewViewModel(library: FailingLibrary())
        await model.refresh()

        XCTAssertNotNil(model.failureMessage)
        XCTAssertTrue(model.items.isEmpty)
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
