import XCTest
@testable import DupeCore

final class LiveScanStateTests: XCTestCase {

    private func running(completed: Int, total: Int, stage: ScanProgress.Stage = .hashing) -> LiveScanState {
        LiveScanState(phase: .scanning, stage: stage, completed: completed, total: total)
    }

    func testTheBarTracksWhatHasBeenRead() {
        XCTAssertEqual(running(completed: 250, total: 1_000).fraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(running(completed: 0, total: 1_000).fraction, 0)
    }

    func testAnEmptyLibraryDoesNotDivideByZero() {
        XCTAssertEqual(running(completed: 0, total: 0).fraction, 0)
    }

    func testCountsCannotRunPastTheirTotal() {
        let state = running(completed: 9_999, total: 100)
        XCTAssertEqual(state.completed, 100)
        XCTAssertEqual(state.fraction, 1)
    }

    func testNegativesAreClampedRatherThanRendered() {
        let state = LiveScanState(
            phase: .scanning,
            stage: .hashing,
            completed: -5,
            total: -100,
            candidateCount: -3,
            reclaimableBytes: -7
        )
        XCTAssertEqual(state.completed, 0)
        XCTAssertEqual(state.total, 0)
        XCTAssertEqual(state.candidateCount, 0)
        XCTAssertEqual(state.reclaimableBytes, 0)
    }

    /// A bar that stops short and then says "done" reads as something having gone wrong.
    func testAnEndedScanReadsAsComplete() {
        for phase in [LiveScanState.Phase.finished, .cancelled, .failed] {
            let state = LiveScanState(phase: phase, stage: .matching, completed: 94, total: 100)
            XCTAssertEqual(state.fraction, 1, "\(phase) should not leave the bar short")
        }
    }

    func testAHeldScanIsStillARunningScan() {
        let state = LiveScanState(phase: .paused, stage: .hashing, completed: 10, total: 100)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.fraction, 0.1, accuracy: 0.0001)
        XCTAssertEqual(state.headline, "Paused")
        XCTAssertEqual(state.detail, "Held at 10 of 100")
        XCTAssertEqual(state.compactValue, "", "the pause glyph beside it already says this")
    }

    func testARunningScanSaysWhatItIsDoingAndHowFar() {
        let state = running(completed: 10, total: 100, stage: .sampling)
        XCTAssertEqual(state.headline, "Scanning")
        XCTAssertEqual(state.detail, "Sampling video · 10 of 100")
        XCTAssertEqual(state.compactValue, "10%")
    }

    func testAFinishedScanLeadsWithWhatItFound() {
        let state = LiveScanState(
            phase: .finished,
            stage: .planning,
            completed: 100,
            total: 100,
            candidateCount: 1,
            reclaimableBytes: 2_000_000_000
        )
        XCTAssertEqual(state.headline, "Found space")
        XCTAssertTrue(state.detail.contains("1 item"), state.detail)
        XCTAssertFalse(state.detail.contains("1 items"), "\"1 items\" is a formatting bug")
    }

    func testAFinishedScanThatFoundNothingSaysSoRatherThanShowingZero() {
        let state = LiveScanState(phase: .finished, stage: .planning, completed: 100, total: 100)
        XCTAssertEqual(state.headline, "All clean")
        XCTAssertEqual(state.detail, "No duplicates worth removing")
        XCTAssertFalse(state.foundSomething)
    }

    /// The app deletes nothing on its own, and a surface people see from the Lock Screen is the
    /// worst possible place to imply otherwise.
    func testACancelledScanSaysNothingWasDeleted() {
        let state = LiveScanState(phase: .cancelled, stage: .hashing, completed: 40, total: 100)
        XCTAssertEqual(state.headline, "Stopped")
        XCTAssertEqual(state.detail, "Nothing was deleted")
    }

    func testAFailedScanPointsSomewhere() {
        let state = LiveScanState(phase: .failed, stage: .hashing, completed: 40, total: 100)
        XCTAssertEqual(state.headline, "Scan failed")
        XCTAssertFalse(state.detail.isEmpty)
    }

    /// The compact slots in the Dynamic Island are a few characters wide, and a value that
    /// overflows is silently truncated rather than reported.
    func testEveryCompactValueFitsTheIslandsSmallestSlot() {
        let states: [LiveScanState] = [
            running(completed: 0, total: 100),
            running(completed: 100, total: 100),
            LiveScanState(phase: .paused, stage: .hashing, completed: 1, total: 3),
            LiveScanState(
                phase: .finished,
                stage: .planning,
                completed: 1,
                total: 1,
                candidateCount: 900,
                reclaimableBytes: 999_000_000_000
            ),
            LiveScanState(phase: .cancelled, stage: .hashing, completed: 1, total: 2),
            LiveScanState(phase: .failed, stage: .hashing, completed: 1, total: 2)
        ]

        for state in states {
            XCTAssertLessThanOrEqual(
                state.compactValue.count, 4,
                "\(state.phase) renders \(state.compactValue), which will be truncated"
            )
        }
    }

    /// A five-digit library read as a phone number before this.
    func testLargeCountsAreGrouped() {
        let state = running(completed: 1_204, total: 23_841, stage: .fingerprinting)
        XCTAssertTrue(state.detail.contains(1_204.formatted()), state.detail)
        XCTAssertTrue(state.detail.contains(23_841.formatted()), state.detail)
    }

    /// The island has three glyphs; the Lock Screen card has a line. They are not the same
    /// number written differently — they are the same number written to the room available.
    func testTheLockScreenGetsTheFullFigureAndTheIslandTheShortOne() {
        let state = LiveScanState(
            phase: .finished,
            stage: .planning,
            completed: 1,
            total: 1,
            candidateCount: 12,
            reclaimableBytes: 4_300_000_000
        )
        XCTAssertEqual(state.compactValue, "4.3G")
        XCTAssertEqual(state.displayValue, ByteText.string(4_300_000_000))
        XCTAssertNotEqual(state.displayValue, state.compactValue)
    }

    func testEveryPhaseHasSomethingToSayAndSomethingToDraw() {
        for phase in [LiveScanState.Phase.scanning, .paused, .finished, .cancelled, .failed] {
            let state = LiveScanState(phase: phase, stage: .matching, completed: 1, total: 2)
            XCTAssertFalse(state.headline.isEmpty)
            XCTAssertFalse(state.detail.isEmpty)
            XCTAssertFalse(state.symbolName.isEmpty)
            XCTAssertFalse(state.accessibilityDescription.isEmpty)
        }
    }

    func testEveryStageHasAShortLabel() {
        for stage in ScanProgress.Stage.allCases {
            let label = running(completed: 1, total: 2, stage: stage).stageLabel
            XCTAssertFalse(label.isEmpty)
            XCTAssertLessThanOrEqual(label.count, 16, "\(stage) label is too long for the island")
        }
    }

    /// The state crosses a process boundary on its way to the widget extension.
    func testTheStateSurvivesTheTripToTheWidget() throws {
        let original = LiveScanState.preview
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LiveScanState.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

final class LiveScanPublishPolicyTests: XCTestCase {

    private let policy = LiveScanPublishPolicy(minimumInterval: 1.5)
    private let start = Date(timeIntervalSince1970: 1_000)

    private func running(_ completed: Int, stage: ScanProgress.Stage = .hashing) -> LiveScanState {
        LiveScanState(phase: .scanning, stage: stage, completed: completed, total: 1_000)
    }

    func testTheFirstUpdateAlwaysGoesThrough() {
        XCTAssertTrue(
            policy.shouldPublish(running(0), after: nil, publishedAt: nil, now: start)
        )
    }

    func testOneItemOutOfThousandsIsNotWorthAnUpdate() {
        XCTAssertFalse(
            policy.shouldPublish(
                running(11),
                after: running(10),
                publishedAt: start,
                now: start.addingTimeInterval(2)
            )
        )
    }

    func testThePercentageMovingIsWorthAnUpdate() {
        XCTAssertTrue(
            policy.shouldPublish(
                running(20),
                after: running(10),
                publishedAt: start,
                now: start.addingTimeInterval(2)
            )
        )
    }

    func testNotTwiceInsideTheSameSecondAndAHalf() {
        XCTAssertFalse(
            policy.shouldPublish(
                running(500),
                after: running(10),
                publishedAt: start,
                now: start.addingTimeInterval(0.5)
            ),
            "ActivityKit budgets these; a fast scan must not spend the budget in ten seconds"
        )
    }

    func testAChangeOfStageIsNewsWhateverTheClockSays() {
        XCTAssertTrue(
            policy.shouldPublish(
                running(11, stage: .matching),
                after: running(10, stage: .hashing),
                publishedAt: start,
                now: start.addingTimeInterval(0.1)
            )
        )
    }

    func testPausingIsNewsImmediately() {
        let paused = LiveScanState(phase: .paused, stage: .hashing, completed: 10, total: 1_000)
        XCTAssertTrue(
            policy.shouldPublish(
                paused,
                after: running(10),
                publishedAt: start,
                now: start.addingTimeInterval(0.01)
            )
        )
    }

    func testTheEndIsTheOneUpdateNobodyMayMiss() {
        for phase in [LiveScanState.Phase.finished, .cancelled, .failed] {
            let ended = LiveScanState(phase: phase, stage: .planning, completed: 999, total: 1_000)
            XCTAssertTrue(
                policy.shouldPublish(
                    ended,
                    after: running(999),
                    publishedAt: start,
                    now: start.addingTimeInterval(0.01)
                ),
                "\(phase) was withheld"
            )
        }
    }
}
