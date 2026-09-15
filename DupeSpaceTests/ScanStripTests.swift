import XCTest
import DupeCore
@testable import DupeSpace

/// The strip that carries a running scan onto every other screen.
///
/// The decision is tested, not the drawing. What the strip has to get right is when it appears
/// at all, and whether the reading it shows agrees with the one on the scan screen — a strip
/// that says 100% over a card that says 99% is worse than no strip, because the person has no
/// way to tell which of the two is lying.
final class ScanStripTests: XCTestCase {

    private func progress(
        _ stage: ScanProgress.Stage = .hashing,
        completed: Int = 0,
        total: Int = 100
    ) -> ScanProgress {
        ScanProgress(stage: stage, completed: completed, total: total)
    }

    // MARK: - When it is there at all

    func testNothingIsDrawnWhenNoScanIsRunning() {
        XCTAssertNil(
            ScanStrip.state(isScanning: false, isPaused: false, progress: nil, isShowingScan: false),
            "the strip costs every screen in the app its top inset; it may only take that when there is a scan to report"
        )
    }

    func testNothingIsDrawnOnTheScanScreenItself() {
        XCTAssertNil(
            ScanStrip.state(
                isScanning: true,
                isPaused: false,
                progress: progress(completed: 40),
                isShowingScan: true
            ),
            "the scan screen already draws this reading in its progress card; two of them is a rendering fault, not a feature"
        )
    }

    func testAHeldScanStillDisappearsOnTheScanScreen() {
        XCTAssertNil(
            ScanStrip.state(
                isScanning: true,
                isPaused: true,
                progress: progress(completed: 40),
                isShowingScan: true
            ),
            "being paused is not a reason to draw a second copy of the card the scan screen is already showing"
        )
    }

    func testARunningScanIsReportedEverywhereElse() {
        XCTAssertNotNil(
            ScanStrip.state(
                isScanning: true,
                isPaused: false,
                progress: progress(completed: 40),
                isShowingScan: false
            )
        )
    }

    // MARK: - What it says

    func testTheStripNamesTheStageTheScanIsIn() {
        let state = ScanStrip.state(
            isScanning: true,
            isPaused: false,
            progress: progress(.fingerprinting, completed: 10),
            isShowingScan: false
        )
        XCTAssertEqual(
            state?.title,
            ScanCopy.title(for: .fingerprinting),
            "the words are ScanCopy's; a second set of stage names in this file would drift from the scan screen's"
        )
    }

    func testThePercentRoundsTheSameWayTheScanScreenDoes() {
        let state = ScanStrip.state(
            isScanning: true,
            isPaused: false,
            progress: progress(completed: 336, total: 1000),
            isShowingScan: false
        )
        XCTAssertEqual(
            state?.percent,
            34,
            "the scan screen rounds 33.6 to 34; truncating here would put the strip a point behind the card it links to"
        )
    }

    func testAHeldScanSaysSoRatherThanLookingStuck() {
        let state = ScanStrip.state(
            isScanning: true,
            isPaused: true,
            progress: progress(completed: 40),
            isShowingScan: false
        )
        XCTAssertEqual(state?.isPaused, true)
        XCTAssertEqual(
            state?.percent,
            40,
            "a paused scan keeps its reading — hiding the number would make a deliberate hold look like a crash"
        )
    }

    // MARK: - Edge cases

    func testAScanThatHasNotReportedYetStillDrawsSomething() {
        let state = ScanStrip.state(isScanning: true, isPaused: false, progress: nil, isShowingScan: false)
        XCTAssertEqual(state?.percent, 0)
        XCTAssertEqual(
            state?.title,
            ScanCopy.title(for: .bucketing),
            "the first stage is where a scan starts; an empty strip in the gap before the first event is a flicker"
        )
    }

    func testAnEmptyLibraryDoesNotDivideByZero() {
        let state = ScanStrip.state(
            isScanning: true,
            isPaused: false,
            progress: progress(completed: 0, total: 0),
            isShowingScan: false
        )
        XCTAssertEqual(state?.percent, 0)
        XCTAssertEqual(state?.fraction, 0)
    }

    func testTheBarNeverGoesPastFull() {
        let state = ScanStrip.state(
            isScanning: true,
            isPaused: false,
            progress: progress(completed: 5_000, total: 4_000),
            isShowingScan: false
        )
        XCTAssertEqual(state?.percent, 100)
        XCTAssertEqual(
            state?.fraction,
            1,
            "a stage that overshoots its own total must not draw a bar wider than its track"
        )
    }

    func testEveryStageHasWordsOfItsOwn() {
        let titles = ScanProgress.Stage.allCases.map { stage in
            ScanStrip.state(
                isScanning: true,
                isPaused: false,
                progress: progress(stage),
                isShowingScan: false
            )?.title
        }
        XCTAssertEqual(titles.compactMap { $0 }.count, ScanProgress.Stage.allCases.count)
        XCTAssertEqual(
            Set(titles.compactMap { $0 }).count,
            ScanProgress.Stage.allCases.count,
            "a stage added later that falls through to another stage's words would be invisible here"
        )
    }

    // MARK: - Spoken

    func testTheReadingIsSpokenAsWellAsDrawn() {
        let state = ScanStrip.state(
            isScanning: true,
            isPaused: false,
            progress: progress(.matching, completed: 34, total: 100),
            isShowingScan: false
        )
        XCTAssertEqual(state?.accessibilityValue, "\(ScanCopy.title(for: .matching)), 34 percent")
    }

    func testVoiceOverIsToldAboutAHoldRatherThanLeftToInferItFromATint() {
        let running = ScanStrip.state(
            isScanning: true,
            isPaused: false,
            progress: progress(completed: 40),
            isShowingScan: false
        )
        let held = ScanStrip.state(
            isScanning: true,
            isPaused: true,
            progress: progress(completed: 40),
            isShowingScan: false
        )
        XCTAssertEqual(running?.accessibilityLabel, "Scan in progress")
        XCTAssertEqual(
            held?.accessibilityLabel,
            "Scan paused",
            "the hold is drawn as a colour and a glyph; neither reaches VoiceOver on its own"
        )
    }
}
