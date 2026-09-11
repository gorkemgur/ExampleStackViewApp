import XCTest

/// Walks the whole flow the way a person would: open the app, start a scan, read the result.
/// Backed by the stub library and analyzer, so the numbers below are facts about the app's
/// logic rather than about whatever is on the runner.
final class ScanUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func openScanScreen() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "the scan entry point was never reachable")
        entry.tap()
        XCTAssertTrue(
            app.buttons["scan.start"].waitForExistence(timeout: 20),
            "the scan screen did not open"
        )
    }

    func testScanFindsTheFixtureDuplicatesAndRanksThem() {
        openScanScreen()
        app.buttons["scan.start"].tap()

        XCTAssertTrue(
            app.staticTexts["scan.total"].waitForExistence(timeout: 60),
            "the scan never produced a total"
        )

        // Two byte-identical videos.
        XCTAssertTrue(app.staticTexts["scan.tier.0"].exists, "identical copies were not reported")
        // A messaging-app re-encode next to its full-size original.
        XCTAssertTrue(app.staticTexts["scan.tier.1"].exists, "the inferior re-send was not reported")
        // Burst frames, which must never be pre-ticked.
        XCTAssertTrue(app.staticTexts["scan.tier.2"].exists, "burst leftovers were not reported")
    }

    func testScanReportsWhatItDeliberatelyDidNotRead() {
        openScanScreen()
        app.buttons["scan.start"].tap()

        XCTAssertTrue(app.staticTexts["scan.total"].waitForExistence(timeout: 60))

        let cloud = app.staticTexts["scan.cloud"]
        for _ in 0..<8 where !cloud.exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            cloud.exists,
            "items left in iCloud must be reported, not silently skipped"
        )
    }

    func testScanScreenOffersACancelWhileItRuns() {
        openScanScreen()
        XCTAssertFalse(app.buttons["scan.cancel"].exists, "cancel belongs to a running scan only")
        app.buttons["scan.start"].tap()
        XCTAssertTrue(app.staticTexts["scan.total"].waitForExistence(timeout: 60))
        XCTAssertFalse(app.buttons["scan.cancel"].exists, "cancel must disappear once the scan is done")
    }
}
