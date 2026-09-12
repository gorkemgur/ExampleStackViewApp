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

    /// History is a destination off the overview rather than a tab, so getting to it means
    /// getting back to the overview first. Popping by the navigation bar's leading button is
    /// what a person does, and it works from however deep the test happens to be.
    private func openHistory() {
        let entry = app.buttons["history.open"]

        if !entry.waitForExistence(timeout: 10) {
            // Named rather than taken by position: the overview's own bar has trailing items at
            // index 0, and tapping one of those instead of a back button opens a sheet.
            for _ in 0..<3 where !entry.exists {
                let back = ["Find duplicates", "Review", "DupeSpace", "Back"]
                    .map { app.navigationBars.buttons[$0] }
                    .first { $0.exists }
                guard let back else { break }
                back.tap()
            }
        }

        XCTAssertTrue(entry.waitForExistence(timeout: 30), "there is no way in to History")
        entry.tap()
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

    func testAScanIsRecordedAndTheRecordCanBeCleared() {
        runScan()
        openHistory()

        XCTAssertTrue(
            app.staticTexts["history.scan.headline"].waitForExistence(timeout: 20),
            "a completed scan was not written down"
        )
        XCTAssertFalse(app.staticTexts["history.empty"].exists)

        app.buttons["history.clear"].tap()
        app.buttons["Clear the record"].tap()

        XCTAssertTrue(
            app.staticTexts["history.empty"].waitForExistence(timeout: 15),
            "clearing the record should leave the empty state"
        )
    }

    /// Delete, then open the receipt and read what was kept in each item's place — the whole
    /// reason for keeping one.
    func testADeletionLeavesAReceiptYouCanOpen() {
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

        let headline = app.staticTexts["history.deletion.headline"]
        XCTAssertTrue(headline.exists, "the deletion was not recorded")
        headline.tap()

        let kept = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'kept '")).firstMatch
        XCTAssertTrue(kept.waitForExistence(timeout: 10), "the receipt does not say what was kept")
    }
}
