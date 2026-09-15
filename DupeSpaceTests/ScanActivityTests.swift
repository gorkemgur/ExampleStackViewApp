import XCTest
import DupeCore
@testable import DupeSpace

/// Stands in for ActivityKit, which refuses to start anything outside a real, foregrounded app.
/// What matters here is what the scan publishes, not that iOS drew it.
@MainActor
final class RecordingScanActivity: ScanActivityPresenting {

    private(set) var startedWith: (items: Int, state: LiveScanState)?
    private(set) var updates: [LiveScanState] = []
    private(set) var ended: LiveScanState?

    func start(libraryItemCount: Int, state: LiveScanState) {
        startedWith = (libraryItemCount, state)
    }

    func update(_ state: LiveScanState) {
        updates.append(state)
    }

    func finish(_ state: LiveScanState) {
        ended = state
    }
}

@MainActor
final class ScanActivityTests: XCTestCase {

    private func waitUntilFinished(_ model: ScanStore, timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while model.isScanning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testAScanPutsItselfOnTheLockScreenBeforeItReadsAnything() async {
        let activity = RecordingScanActivity()
        let items = StubMediaLibrary.sampleItems()
        let model = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture(), activity: activity)

        model.start(items: items)

        let started = try? XCTUnwrap(activity.startedWith)
        XCTAssertEqual(started?.items, items.count)
        XCTAssertEqual(started?.state.phase, .scanning)
        XCTAssertEqual(started?.state.total, items.count)
        XCTAssertEqual(started?.state.fraction, 0)

        await waitUntilFinished(model)
    }

    func testTheLiveSurfaceFollowsTheScanAndEndsWithWhatItFound() async {
        let activity = RecordingScanActivity()
        let model = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture(), activity: activity)

        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)

        XCTAssertFalse(activity.updates.isEmpty, "a scan that never reported progress is not live")
        XCTAssertTrue(
            activity.updates.allSatisfy(\.isRunning),
            "only a finished scan may be published as finished"
        )

        let ended = try? XCTUnwrap(activity.ended)
        XCTAssertEqual(ended?.phase, .finished)
        XCTAssertEqual(ended?.reclaimableBytes, model.result?.reclaimableBytes)
        XCTAssertEqual(ended?.candidateCount, model.result?.candidates.count)
        XCTAssertEqual(ended?.fraction, 1)
    }

    /// The numbers on a Lock Screen are read by someone who cannot see the app, so a total that
    /// is an estimate would be worse than no total at all.
    func testNothingIsClaimedFoundWhileTheScanIsStillRunning() async {
        let activity = RecordingScanActivity()
        let model = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture(), activity: activity)

        model.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(model)

        XCTAssertTrue(activity.updates.allSatisfy { $0.reclaimableBytes == 0 })
        XCTAssertTrue(activity.updates.allSatisfy { !$0.foundSomething })
    }

    func testHoldingTheScanShowsAsHeldAndResumingUndoesIt() async {
        let activity = RecordingScanActivity()
        let slow = StubAssetAnalyzer(digests: [:], hashes: [:], stepDelay: .milliseconds(40))
        let model = makeScanStore(analyzer: slow, activity: activity)

        model.start(items: StubMediaLibrary.sampleItems())
        model.pause()

        XCTAssertEqual(activity.updates.last?.phase, .paused)

        model.resume()
        XCTAssertEqual(activity.updates.last?.phase, .scanning)

        model.cancel()
        await waitUntilFinished(model, timeout: 20)
    }

    func testACancelledScanEndsTheLiveSurfaceSayingNothingWasDeleted() async {
        let activity = RecordingScanActivity()
        let slow = StubAssetAnalyzer(digests: [:], hashes: [:], stepDelay: .milliseconds(50))
        let model = makeScanStore(analyzer: slow, activity: activity)

        model.start(items: StubMediaLibrary.sampleItems())
        model.cancel()
        await waitUntilFinished(model)

        XCTAssertEqual(activity.ended?.phase, .cancelled)
        XCTAssertEqual(activity.ended?.detail, "Nothing was deleted")
    }

    /// The Live Activity is a convenience. A device that will not show one — an iPad, or a user
    /// who turned them off — still gets a scan.
    func testAScanWithNoLiveSurfaceRunsExactlyTheSame() async {
        let withActivity = makeScanStore(
            analyzer: StubAssetAnalyzer.uiTestFixture(),
            activity: RecordingScanActivity()
        )
        let without = makeScanStore(analyzer: StubAssetAnalyzer.uiTestFixture(), activity: nil)

        withActivity.start(items: StubMediaLibrary.sampleItems())
        without.start(items: StubMediaLibrary.sampleItems())
        await waitUntilFinished(withActivity)
        await waitUntilFinished(without)

        XCTAssertEqual(
            withActivity.result?.candidates.map(\.id),
            without.result?.candidates.map(\.id)
        )
    }
}
