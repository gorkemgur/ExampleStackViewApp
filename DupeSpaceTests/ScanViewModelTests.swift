import XCTest
import DupeCore
@testable import DupeSpace

@MainActor
final class ScanViewModelTests: XCTestCase {

    private func waitUntilFinished(_ model: ScanViewModel, timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while model.isScanning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testScanningTheFixtureFindsTheIdenticalVideos() async {
        let model = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture())
        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)

        guard let result = model.result else { return XCTFail("scan produced no result") }

        let identical = result.candidates.filter { $0.tier == .identical }
        XCTAssertEqual(identical.map(\.id), ["video-holiday-copy"])
        XCTAssertTrue(identical.allSatisfy(\.isPreSelected))
        XCTAssertNil(model.failure)
    }

    func testTheFavouritedOriginalIsNeverTheOneOffered() async {
        let model = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture())
        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)

        guard let result = model.result else { return XCTFail("scan produced no result") }
        XCTAssertFalse(
            result.candidates.contains { $0.id == "photo-cliff" },
            "a favourited, album-filed original must never be a deletion candidate"
        )
        XCTAssertTrue(result.candidates.contains { $0.id == "photo-cliff-resend" })
    }

    func testBurstFramesAreFoundButNeverPreSelected() async {
        let model = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture())
        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)

        guard let result = model.result else { return XCTFail("scan produced no result") }
        let burst = result.candidates.filter { $0.tier == .burstLeftover }
        XCTAssertFalse(burst.isEmpty, "the burst was not detected")
        XCTAssertTrue(burst.allSatisfy { !$0.isPreSelected })
    }

    func testWhateverIsPreSelectedSurvivesTheValidator() async {
        let model = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture())
        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)

        guard let result = model.result else { return XCTFail("scan produced no result") }
        let violations = CleanupValidator.validate(
            selection: Set(result.candidates.filter(\.isPreSelected).map(\.id)),
            decisions: result.decisions,
            knownItemIDs: Set(result.items.keys)
        )
        XCTAssertEqual(violations, [])
    }

    func testAFinishedScanLeavesARecordBehind() async {
        let history = HistoryViewModel(store: InMemoryHistoryStore())
        await history.load()

        let model = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture(), history: history)
        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)

        XCTAssertEqual(history.log.scans.count, 1)
        let record = history.log.scans[0]
        XCTAssertEqual(record.itemsScanned, StubMediaLibrary.sampleItems().count)
        XCTAssertTrue(record.foundSomething)
        XCTAssertEqual(record.reclaimableBytes, model.result?.reclaimableBytes)
    }

    func testACancelledScanLeavesNoRecord() async {
        let history = HistoryViewModel(store: InMemoryHistoryStore())
        await history.load()

        let model = ScanViewModel(
            analyzer: StubAssetAnalyzer(digests: [:], hashes: [:], stepDelay: .milliseconds(50)),
            history: history
        )
        model.start(items: StubMediaLibrary.sampleItems())
        model.cancel()
        await waitUntilFinished(model)

        XCTAssertTrue(history.log.scans.isEmpty, "a scan that did not finish did not happen")
    }

    func testCancellingLeavesNoResultAndNoError() async {
        let slow = StubAssetAnalyzer(
            digests: [:],
            hashes: [:],
            stepDelay: .milliseconds(50)
        )
        let model = ScanViewModel(analyzer: slow)
        model.start(items: StubMediaLibrary.sampleItems())
        model.cancel()
        await waitUntilFinished(model)

        XCTAssertNil(model.result)
        XCTAssertNil(model.failure)
        XCTAssertFalse(model.isScanning)
    }
}
