import XCTest

/// The receipt has to survive the round trip: do something, switch tabs, and find it written
/// down. Each test relaunches the app against a fresh in-memory log, so what these assertions
/// see is what this run produced.
final class HistoryUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func openHistory() {
        let tab = app.tabBars.buttons["History"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "the History tab is missing")
        tab.tap()
    }

    private func runScan() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20))
        app.buttons["scan.start"].tap()
        XCTAssertTrue(app.staticTexts["scan.total"].waitForExistence(timeout: 60))
    }

    func testHistoryStartsEmpty() {
        openHistory()
        XCTAssertTrue(
            app.staticTexts["history.empty"].waitForExistence(timeout: 15),
            "a fresh install has nothing to show and should say so"
        )
    }

    func testAScanIsRecorded() {
        runScan()
        openHistory()

        XCTAssertTrue(
            app.staticTexts["history.scan.headline"].waitForExistence(timeout: 20),
            "a completed scan was not written down"
        )
        XCTAssertFalse(app.staticTexts["history.empty"].exists)
    }

    func testADeletionLeavesAReceipt() {
        runScan()

        let review = app.buttons["scan.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 30))
        review.tap()

        XCTAssertTrue(app.staticTexts["review.total"].waitForExistence(timeout: 20))
        app.buttons["review.delete"].tap()

        XCTAssertTrue(app.staticTexts["confirm.total"].waitForExistence(timeout: 20))
        app.buttons["confirm.delete"].tap()
        XCTAssertTrue(app.staticTexts["review.result"].waitForExistence(timeout: 30))

        openHistory()

        XCTAssertTrue(
            app.staticTexts["history.total"].waitForExistence(timeout: 20),
            "the lifetime total never appeared"
        )
        XCTAssertTrue(
            app.staticTexts["history.deletion.headline"].exists,
            "the deletion was not recorded"
        )
    }

    func testTheReceiptCanBeOpenedToSeeWhatWasKept() {
        testADeletionLeavesAReceipt()

        app.staticTexts["history.deletion.headline"].tap()

        // The expanded rows name the survivor, which is the whole point of keeping a receipt.
        let kept = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'kept '")).firstMatch
        XCTAssertTrue(kept.waitForExistence(timeout: 10), "the receipt does not say what was kept")
    }

    func testClearingTheHistoryEmptiesIt() {
        runScan()
        openHistory()
        XCTAssertTrue(app.staticTexts["history.scan.headline"].waitForExistence(timeout: 20))

        app.buttons["history.clear"].tap()
        app.buttons["Clear the record"].tap()

        XCTAssertTrue(
            app.staticTexts["history.empty"].waitForExistence(timeout: 15),
            "clearing the record should leave the empty state"
        )
    }
}
