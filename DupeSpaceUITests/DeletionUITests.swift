import XCTest

/// The last stretch, which is the one nothing else covers: the confirmation, the instrument
/// that runs while the deletion runs, and what the screen says once it is over.
///
/// These are deliberately about the *flow*, not about how the figure looks. What it looks like
/// is `SweepSceneTests`' job and it is settled there in numbers; what a UI test can prove is
/// that the thing appears when the work starts, that it is gone when the work is done, and that
/// the screen behind it ends up telling the truth.
final class DeletionUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func openConfirmation() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20))
        app.buttons["scan.start"].tap()

        let review = app.buttons["scan.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 60), "the review entry point never appeared")
        review.tap()

        XCTAssertTrue(app.staticTexts["review.total"].waitForExistence(timeout: 20))
        app.buttons["review.delete"].tap()
        XCTAssertTrue(
            app.staticTexts["confirm.total"].waitForExistence(timeout: 20),
            "the confirmation sheet did not open"
        )
    }

    /// The sheet has to lead with what comes back and when, and it has to offer the export
    /// before it offers the deletion — the whole point of that card is that it is reachable
    /// while the decision is still reversible.
    func testTheConfirmationLeadsWithTheFigureAndOffersToKeepTheOriginals() {
        openConfirmation()

        XCTAssertTrue(app.staticTexts["confirm.breakdown"].exists, "the ledger is the auditable part")
        XCTAssertTrue(app.buttons["confirm.export"].exists, "the export has to be offered before the red key")
        XCTAssertTrue(app.buttons["confirm.delete"].isEnabled)
    }

    /// Cancelling has to leave the selection exactly as it was. A confirmation that quietly
    /// clears what you picked is worse than no confirmation.
    func testCancellingChangesNothing() {
        openConfirmation()

        let before = app.staticTexts["review.count"].label
        app.buttons["confirm.cancel"].tap()

        XCTAssertTrue(app.staticTexts["review.total"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["review.count"].label, before)
        XCTAssertTrue(app.buttons["review.delete"].isEnabled)
    }

    /// The instrument replaces the red key while the work runs, and the key does not come back
    /// — a control that returns after the deletion is a control that invites a second tap.
    func testTheKeyIsSpentAndTheInstrumentTakesItsPlace() {
        openConfirmation()

        app.buttons["confirm.delete"].tap()

        // By descendant rather than by element type: it is one accessibility element by
        // construction — `children: .ignore` — and which bucket XCUITest files that in is not
        // something a test should be asserting.
        let sweeper = app.descendants(matching: .any).matching(identifier: "sweeper").firstMatch
        XCTAssertTrue(sweeper.waitForExistence(timeout: 10), "nothing was drawn while the deletion ran")

        // The sheet dismisses itself once the arrival has been seen, so the key must be gone
        // rather than merely disabled.
        XCTAssertTrue(
            app.staticTexts["review.freed"].waitForExistence(timeout: 60),
            "the success reading never arrived"
        )
        XCTAssertFalse(app.buttons["confirm.delete"].exists)
    }

    /// What the screen says afterwards. The figure has to be there — a success step with no
    /// quantity on it, in an app whose identity is a byte readout, is a missing one — and so
    /// does the way to the receipt.
    func testTheSuccessStepSaysWhatWentAndWhereTheRecordIs() {
        openConfirmation()
        app.buttons["confirm.delete"].tap()

        XCTAssertTrue(app.staticTexts["review.freed"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["review.result"].exists, "how many went")
        XCTAssertTrue(app.buttons["review.receipt"].exists, "the way to the receipt")

        let freed = app.staticTexts["review.freed"].label
        XCTAssertFalse(freed.isEmpty)
        XCTAssertFalse(freed.hasPrefix("0 "), "the figure must be what actually went, not zero")
    }

    /// And the list has to stop offering what is no longer there. This is the assertion that
    /// would fail if `deletedIDs` ever stopped feeding back into the sections.
    func testTheDeletedCopiesStopBeingOffered() {
        openConfirmation()
        app.buttons["confirm.delete"].tap()

        XCTAssertTrue(app.staticTexts["review.freed"].waitForExistence(timeout: 60))
        XCTAssertEqual(app.staticTexts["review.count"].label, "0 selected")
        XCTAssertFalse(app.buttons["review.delete"].isEnabled, "nothing is selected, so nothing may be deleted")
    }
}
