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
