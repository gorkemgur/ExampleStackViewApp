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

    func testAReEncodedVideoIsCaughtByItsFramesAlone() async {
        let model = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture())
        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)

        guard let result = model.result else { return XCTFail("scan produced no result") }

        // Nothing in the metadata connects these two: different sizes, different resolutions,
        // different file names. Only the sampled frames do.
        let candidate = result.candidates.first { $0.id == "video-trip-sent" }
        XCTAssertNotNil(candidate, "the re-encoded video was not matched")
        XCTAssertEqual(candidate?.tier, .inferiorCopy)
        XCTAssertEqual(candidate?.keeperID, "video-trip", "the full-size copy is the one that stays")
        XCTAssertTrue(candidate?.isPreSelected ?? false)
    }

    func testTheFullSizeVideoIsNeverTheOneOffered() async {
        let model = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture())
        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)

        guard let result = model.result else { return XCTFail("scan produced no result") }
        XCTAssertFalse(result.candidates.contains { $0.id == "video-trip" })
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

    /// The rescan panel exists because a finished scan used to be the end of the road: the
    /// intro card only draws while `result` is nil, so "No duplicates found" on Strict had no
    /// way on. Starting again has to actually clear the last answer, or the panel would sit
    /// under the previous result forever.
    func testScanningAgainClearsTheLastAnswerFirst() async {
        let model = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture())
        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)
        XCTAssertNotNil(model.result)

        model.start(items: StubMediaLibrary.sampleItems())

        XCTAssertNil(model.result, "the previous result must not survive into the new scan")
        XCTAssertTrue(model.isScanning)
        XCTAssertFalse(model.wasCancelled)
        XCTAssertNil(model.failure)

        await waitUntilFinished(model)
        XCTAssertNotNil(model.result)
    }

    /// And the strictness the user picks for the second run is the one it uses, rather than
    /// whatever the first run was configured with.
    func testTheSecondScanUsesTheStrictnessSetForIt() async {
        // Restored afterwards. `strictness` persists to UserDefaults, and the unit bundle is
        // hosted by the app — so a test that leaves it set changes what every UI test in the
        // same run scans with. That is exactly what happened: this test left it on `loose` and
        // `ScanUITests` then failed to find the burst tier.
        let remembered = UserDefaults.standard.object(forKey: "scan.strictness")
        defer {
            if let remembered {
                UserDefaults.standard.set(remembered, forKey: "scan.strictness")
            } else {
                UserDefaults.standard.removeObject(forKey: "scan.strictness")
            }
        }

        let model = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture())
        model.strictness = .strict
        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)
        let strict = model.result?.candidates.count ?? 0

        model.strictness = .loose
        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)
        let loose = model.result?.candidates.count ?? 0

        XCTAssertGreaterThanOrEqual(loose, strict, "a looser setting cannot find less")
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

    func testAHeldScanStopsAdvancingAndThenFinishes() async {
        let slow = StubAssetAnalyzer(digests: [:], hashes: [:], stepDelay: .milliseconds(40))
        let model = ScanViewModel(analyzer: slow)
        model.start(items: StubMediaLibrary.sampleItems())

        model.pause()
        XCTAssertTrue(model.isPaused)

        // Two readings far enough apart that an unheld scan would certainly have moved on.
        try? await Task.sleep(for: .milliseconds(400))
        let first = model.progress
        try? await Task.sleep(for: .milliseconds(500))
        let second = model.progress

        XCTAssertEqual(first, second, "a held scan must not advance")
        XCTAssertTrue(model.isScanning, "a held scan is still a running scan")
        XCTAssertNil(model.result)

        model.resume()
        XCTAssertFalse(model.isPaused)
        await waitUntilFinished(model, timeout: 30)

        XCTAssertNotNil(model.result, "resuming has to finish the work, not discard it")
    }

    func testCancellingAHeldScanLetsItGo() async {
        let slow = StubAssetAnalyzer(digests: [:], hashes: [:], stepDelay: .milliseconds(30))
        let model = ScanViewModel(analyzer: slow)
        model.start(items: StubMediaLibrary.sampleItems())

        model.pause()
        model.cancel()
        await waitUntilFinished(model, timeout: 20)

        XCTAssertFalse(model.isPaused)
        XCTAssertNil(model.result)
        XCTAssertNil(model.failure)
    }

    func testPausingBeforeAnythingRunsDoesNothing() async {
        let model = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture())
        model.pause()
        XCTAssertFalse(model.isPaused, "there is nothing to hold")
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
