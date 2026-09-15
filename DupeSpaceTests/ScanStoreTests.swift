import XCTest
import DupeCore
@testable import DupeSpace

/// Builds a store over a real engine.
///
/// Shared with `ScanActivityTests` and `ReviewViewModelTests`, which need the same thing. The
/// manager is the real one rather than a stand-in: what these tests are checking is what the
/// store does with what a scan actually reports, and a fake engine would only prove the store
/// can read a script.
@MainActor
func makeScanStore(
    analyzer: any AssetAnalyzing,
    history: (any HistoryRecording)? = nil,
    cache: FileFingerprintCache? = nil,
    activity: (any ScanActivityPresenting)? = nil
) -> ScanStore {
    ScanStore(
        manager: ScanManager(analyzer: analyzer, cache: cache),
        history: history,
        activity: activity
    )
}

@MainActor
final class ScanStoreTests: XCTestCase {

    private func waitUntilFinished(_ store: ScanStore, timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while store.isScanning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func slowAnalyzer(_ step: Duration = .milliseconds(50)) -> StubAssetAnalyzer {
        StubAssetAnalyzer(digests: [:], hashes: [:], stepDelay: step)
    }

    // MARK: - What the scan found

    func testScanningTheFixtureFindsTheIdenticalVideos() async {
        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)

        guard let result = store.result else { return XCTFail("scan produced no result") }

        let identical = result.candidates.filter { $0.tier == .identical }
        XCTAssertEqual(identical.map(\.id), ["video-holiday-copy"])
        XCTAssertTrue(identical.allSatisfy(\.isPreSelected))
        XCTAssertNil(store.failure)
    }

    func testTheFavouritedOriginalIsNeverTheOneOffered() async {
        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)

        guard let result = store.result else { return XCTFail("scan produced no result") }
        XCTAssertFalse(
            result.candidates.contains { $0.id == "photo-cliff" },
            "a favourited, album-filed original must never be a deletion candidate"
        )
        XCTAssertTrue(result.candidates.contains { $0.id == "photo-cliff-resend" })
    }

    func testAReEncodedVideoIsCaughtByItsFramesAlone() async {
        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)

        guard let result = store.result else { return XCTFail("scan produced no result") }

        // Nothing in the metadata connects these two: different sizes, different resolutions,
        // different file names. Only the sampled frames do.
        let candidate = result.candidates.first { $0.id == "video-trip-sent" }
        XCTAssertNotNil(candidate, "the re-encoded video was not matched")
        XCTAssertEqual(candidate?.tier, .inferiorCopy)
        XCTAssertEqual(candidate?.keeperID, "video-trip", "the full-size copy is the one that stays")
        XCTAssertTrue(candidate?.isPreSelected ?? false)
    }

    func testTheFullSizeVideoIsNeverTheOneOffered() async {
        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)

        guard let result = store.result else { return XCTFail("scan produced no result") }
        XCTAssertFalse(result.candidates.contains { $0.id == "video-trip" })
    }

    func testBurstFramesAreFoundButNeverPreSelected() async {
        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)

        guard let result = store.result else { return XCTFail("scan produced no result") }
        let burst = result.candidates.filter { $0.tier == .burstLeftover }
        XCTAssertFalse(burst.isEmpty, "the burst was not detected")
        XCTAssertTrue(burst.allSatisfy { !$0.isPreSelected })
    }

    func testWhateverIsPreSelectedSurvivesTheValidator() async {
        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)

        guard let result = store.result else { return XCTFail("scan produced no result") }
        let violations = CleanupValidator.validate(
            selection: Set(result.candidates.filter(\.isPreSelected).map(\.id)),
            decisions: result.decisions,
            knownItemIDs: Set(result.items.keys)
        )
        XCTAssertEqual(violations, [])
    }

    // MARK: - Scanning again

    /// The rescan panel exists because a finished scan used to be the end of the road: the
    /// intro card only draws while `result` is nil, so "No duplicates found" on Strict had no
    /// way on. Starting again has to actually clear the last answer, or the panel would sit
    /// under the previous result forever.
    func testScanningAgainClearsTheLastAnswerFirst() async {
        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)
        XCTAssertNotNil(store.result)

        store.start(items: StubMediaLibrary.sampleItems())

        XCTAssertNil(store.result, "the previous result must not survive into the new scan")
        XCTAssertTrue(store.isScanning)
        XCTAssertFalse(store.wasCancelled)
        XCTAssertNil(store.failure)

        await waitUntilFinished(store)
        XCTAssertNotNil(store.result)
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

        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())
        store.strictness = .strict
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)
        let strict = store.result?.candidates.count ?? 0

        store.strictness = .loose
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)
        let loose = store.result?.candidates.count ?? 0

        XCTAssertGreaterThanOrEqual(loose, strict, "a looser setting cannot find less")
    }

    /// A scan already running is not restarted by a second tap. The button is hidden while one
    /// runs, but the store is the only thing that can actually promise it.
    func testStartingWhileAScanIsRunningIsIgnored() async {
        let store = makeScanStore(analyzer: slowAnalyzer(.milliseconds(40)))
        store.start(items: StubMediaLibrary.sampleItems())
        store.pause()

        store.start(items: StubMediaLibrary.sampleItems())

        XCTAssertTrue(store.isPaused, "the second start restarted a scan that was already held")
        store.cancel()
        await waitUntilFinished(store, timeout: 20)
    }

    // MARK: - History

    func testAFinishedScanLeavesARecordBehind() async {
        let history = HistoryViewModel(store: InMemoryHistoryStore())
        await history.load()

        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture(), history: history)
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)

        XCTAssertEqual(history.log.scans.count, 1)
        let record = history.log.scans[0]
        XCTAssertEqual(record.itemsScanned, StubMediaLibrary.sampleItems().count)
        XCTAssertTrue(record.foundSomething)
        XCTAssertEqual(record.reclaimableBytes, store.result?.reclaimableBytes)
    }

    func testACancelledScanLeavesNoRecord() async {
        let history = HistoryViewModel(store: InMemoryHistoryStore())
        await history.load()

        let store = makeScanStore(analyzer: slowAnalyzer(), history: history)
        store.start(items: StubMediaLibrary.sampleItems())
        store.cancel()
        await waitUntilFinished(store)

        XCTAssertTrue(history.log.scans.isEmpty, "a scan that did not finish did not happen")
    }

    // MARK: - Holding and stopping

    func testAHeldScanStopsAdvancingAndThenFinishes() async {
        let store = makeScanStore(analyzer: slowAnalyzer(.milliseconds(40)))
        store.start(items: StubMediaLibrary.sampleItems())

        store.pause()
        XCTAssertTrue(store.isPaused)

        // Two readings far enough apart that an unheld scan would certainly have moved on.
        try? await Task.sleep(for: .milliseconds(400))
        let first = store.progress
        try? await Task.sleep(for: .milliseconds(500))
        let second = store.progress

        XCTAssertEqual(first, second, "a held scan must not advance")
        XCTAssertTrue(store.isScanning, "a held scan is still a running scan")
        XCTAssertNil(store.result)

        store.resume()
        XCTAssertFalse(store.isPaused)
        await waitUntilFinished(store, timeout: 30)

        XCTAssertNotNil(store.result, "resuming has to finish the work, not discard it")
    }

    func testCancellingAHeldScanLetsItGo() async {
        let store = makeScanStore(analyzer: slowAnalyzer(.milliseconds(30)))
        store.start(items: StubMediaLibrary.sampleItems())

        store.pause()
        store.cancel()
        await waitUntilFinished(store, timeout: 20)

        XCTAssertFalse(store.isPaused)
        XCTAssertNil(store.result)
        XCTAssertNil(store.failure)
    }

    func testPausingBeforeAnythingRunsDoesNothing() async {
        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())
        store.pause()
        XCTAssertFalse(store.isPaused, "there is nothing to hold")
    }

    func testCancellingLeavesNoResultAndNoError() async {
        let store = makeScanStore(analyzer: slowAnalyzer())
        store.start(items: StubMediaLibrary.sampleItems())
        store.cancel()
        await waitUntilFinished(store)

        XCTAssertNil(store.result)
        XCTAssertNil(store.failure)
        XCTAssertFalse(store.isScanning)
    }

    // MARK: - Going away and coming back

    /// The scan outlives the screen now, so it also has to survive the app being put down — and
    /// "survive" means held, not left reading the library from the background where iOS will
    /// eventually stop it anyway.
    func testGoingToTheBackgroundHoldsARunningScan() async {
        let store = makeScanStore(analyzer: slowAnalyzer(.milliseconds(40)))
        store.start(items: StubMediaLibrary.sampleItems())

        store.enterBackground()

        XCTAssertTrue(store.isPaused)
        store.cancel()
        await waitUntilFinished(store, timeout: 20)
    }

    func testComingBackToTheFrontLetsTheScanFinish() async {
        let store = makeScanStore(analyzer: slowAnalyzer(.milliseconds(40)))
        store.start(items: StubMediaLibrary.sampleItems())

        store.enterBackground()
        store.enterForeground()

        XCTAssertFalse(store.isPaused)
        await waitUntilFinished(store, timeout: 30)
        XCTAssertNotNil(store.result)
    }

    /// The one that needs a flag of its own. Coming back to the front is the app's decision,
    /// not the person's — and it must not quietly undo a hold they chose, which is exactly what
    /// resuming everything on `.active` would do.
    func testComingBackToTheFrontDoesNotUndoAPauseTheUserChose() async {
        let store = makeScanStore(analyzer: slowAnalyzer(.milliseconds(40)))
        store.start(items: StubMediaLibrary.sampleItems())

        store.pause()
        store.enterBackground()
        store.enterForeground()

        XCTAssertTrue(store.isPaused, "the app coming forward is not the user pressing Resume")
        store.cancel()
        await waitUntilFinished(store, timeout: 20)
    }

    /// And the flag has to be let go of again, or the first hold a person ever chooses would
    /// make every later backgrounding permanent.
    func testAUserWhoResumesGetsTheBackgroundHoldBack() async {
        let store = makeScanStore(analyzer: slowAnalyzer(.milliseconds(40)))
        store.start(items: StubMediaLibrary.sampleItems())

        store.pause()
        store.resume()
        store.enterBackground()
        store.enterForeground()

        XCTAssertFalse(store.isPaused, "the user let go of the hold before the app was put down")
        store.cancel()
        await waitUntilFinished(store, timeout: 20)
    }

    func testGoingToTheBackgroundWithNothingRunningHoldsNothing() async {
        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())

        store.enterBackground()
        XCTAssertFalse(store.isPaused)

        store.enterForeground()
        XCTAssertFalse(store.isPaused)
    }

    /// A finished scan is not a running one, and the app being put down must not reopen it.
    func testGoingToTheBackgroundAfterAScanKeepsTheResult() async {
        let store = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture())
        store.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(store)

        store.enterBackground()
        store.enterForeground()

        XCTAssertNotNil(store.result, "the answer went away when the app did")
        XCTAssertFalse(store.isPaused)
        XCTAssertFalse(store.isScanning)
    }

    func testTheLockScreenIsToldWhenTheAppPutsTheScanDown() async {
        let activity = RecordingScanActivity()
        let store = makeScanStore(analyzer: slowAnalyzer(.milliseconds(40)), activity: activity)
        store.start(items: StubMediaLibrary.sampleItems())

        store.enterBackground()

        XCTAssertEqual(
            activity.updates.last?.phase,
            .paused,
            "the Lock Screen went on claiming the scan was reading"
        )
        store.cancel()
        await waitUntilFinished(store, timeout: 20)
    }
}
