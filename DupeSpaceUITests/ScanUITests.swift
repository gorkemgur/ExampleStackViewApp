import XCTest

/// Walks the scan the way a person would, in a single pass: start it, watch it finish, read
/// what it found and what it deliberately left alone.
final class ScanUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testScanFindsTheFixtureDuplicatesRanksThemAndReportsWhatItSkipped() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "the scan entry point was never reachable")
        entry.tap()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20), "the scan screen did not open")
        XCTAssertFalse(app.buttons["scan.cancel"].exists, "cancel belongs to a running scan only")

        app.buttons["scan.start"].tap()

        XCTAssertTrue(
            app.staticTexts["scan.total"].waitForExistence(timeout: 60),
            "the scan never produced a total"
        )
        XCTAssertFalse(app.buttons["scan.cancel"].exists, "cancel must disappear once the scan is done")

        // Two byte-identical videos.
        XCTAssertTrue(app.staticTexts["scan.tier.0"].exists, "identical copies were not reported")
        // A messaging-app re-encode next to its full-size original — photo and video alike.
        XCTAssertTrue(app.staticTexts["scan.tier.1"].exists, "the inferior re-sends were not reported")
        // Burst frames, which must never be pre-ticked.
        XCTAssertTrue(app.staticTexts["scan.tier.2"].exists, "burst leftovers were not reported")

        let cloud = app.staticTexts["scan.cloud"]
        for _ in 0..<8 where !cloud.exists {
            app.swipeUp()
        }
        XCTAssertTrue(cloud.exists, "items left in iCloud must be reported, not silently skipped")
    }

    /// The screen's whole reason to exist as a separate step.
    ///
    /// The overview already carries a "Scan for duplicates" key, so if this screen only
    /// repeats it then it is chrome. It earns the tap by saying what is about to be opened
    /// before it is opened — and the numbers have to be there before the button is pressed,
    /// not after, which is what this asserts.
    func testTheScanScreenSaysWhatItIsAboutToOpenBeforeItOpensAnything() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20))

        let summary = require(
            "scan.plan.summary", in: app,
            "the scan screen never said how much of the library it would read"
        )
        guard summary.exists else { return }
        XCTAssertTrue(
            summary.label.contains("will be opened"),
            "the plan summary read \(summary.label)"
        )
        XCTAssertTrue(
            app.otherElements["scan.plan"].exists || app.staticTexts["scan.plan"].exists,
            "the per-kind ledger was not on the screen"
        )
        XCTAssertTrue(
            app.buttons["scan.start"].isHittable,
            "the ledger must not push the start key off the screen"
        )
    }
}

// MARK: - The strip

/// The scan, seen from a screen that is not the scan screen.
///
/// The scan became the app's rather than the screen's in the previous phase, which is what made
/// this possible *and* what made it necessary: backing out of the scan screen no longer kills
/// the scan, so without a strip there is a job running with nothing on screen to say so.
///
/// The scan is held before backing out rather than raced against. A twenty-eight item fixture
/// finishes in seconds, and a test that has to get off the screen before it does would be a
/// test of how fast the simulator is that day. A hold lasts until somebody lifts it — so what
/// is asserted below is the strip's behaviour, not the machine's timing. It also pins the claim
/// the previous phase made and never proved from outside: the scan is still there after you
/// leave the screen that started it.
final class ScanStripUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // `-slow-scan` is the whole reason this test can exist. See `AppEnvironment`: the
        // fixture scan is otherwise over before a query for its Pause key resolves, which
        // this test measured the hard way.
        app.launchArguments = ["-ui-testing", "-slow-scan"]
        app.launch()
    }

    func testAHeldScanIsReportedOnTheOverviewAndTheStripLeadsBackToIt() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "the scan entry point was never reachable")
        entry.tap()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20), "the scan screen did not open")
        app.buttons["scan.start"].tap()

        let hold = require("scan.pause", in: app, "a running scan offered no way to hold it")
        hold.tap()

        XCTAssertFalse(
            element("scan.strip", in: app).exists,
            "the strip must not draw over the scan screen, which is already showing this reading"
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let strip = require(
            "scan.strip", in: app,
            "a scan that is still running was not reported anywhere after leaving the scan screen"
        )
        XCTAssertEqual(
            strip.label, "Scan paused",
            "the hold is drawn as a tint and a glyph; VoiceOver gets neither unless the label says it"
        )

        strip.tap()

        XCTAssertTrue(
            element("scan.pause", in: app).waitForExistence(timeout: 10),
            "tapping the strip did not land back on the scan it was reporting"
        )
        XCTAssertFalse(
            element("scan.strip", in: app).exists,
            "the strip must go away again once you are looking at the scan itself"
        )

        // Leave nothing running behind this test.
        app.buttons["scan.cancel"].tap()
    }
}
