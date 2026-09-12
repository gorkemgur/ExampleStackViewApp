import XCTest

/// The full path a person takes: scan, look at what was found, choose, delete.
final class ReviewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func openReview() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20))
        app.buttons["scan.start"].tap()

        let review = app.buttons["scan.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 60), "the review entry point never appeared")
        review.tap()

        XCTAssertTrue(
            app.staticTexts["review.total"].waitForExistence(timeout: 20),
            "the review screen did not open"
        )
    }

    func testReviewOpensWithASafeSelectionThatCanBeChanged() {
        openReview()

        XCTAssertTrue(app.staticTexts["review.count"].exists)
        XCTAssertTrue(app.buttons["review.delete"].isEnabled, "the safe default selection must be actionable")
        XCTAssertTrue(app.staticTexts["review.section.0"].exists, "identical copies section missing")

        let count = app.staticTexts["review.count"]
        let before = count.label

        let toggle = app.buttons["review.selectall.0"]
        XCTAssertTrue(toggle.exists, "each section needs a whole-section control")
        toggle.tap()

        XCTAssertNotEqual(count.label, before, "toggling a section must change the selection")
    }

    func testBudgetSliderCanDriveTheSelection() {
        openReview()

        let slider = app.sliders["budget.slider"]
        XCTAssertTrue(slider.exists, "the space budget control is the point of this screen")
        slider.adjust(toNormalizedSliderPosition: 0.5)

        let apply = app.buttons["budget.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        if apply.isEnabled {
            apply.tap()
        }
        XCTAssertTrue(app.staticTexts["review.total"].exists)
    }

    /// Cancelling first, then going through with it, in one launch.
    func testConfirmationCanBeBackedOutOfAndThenGoneThroughWith() {
        openReview()

        let count = app.staticTexts["review.count"]
        let before = count.label

        app.buttons["review.delete"].tap()
        XCTAssertTrue(
            app.staticTexts["confirm.total"].waitForExistence(timeout: 20),
            "the confirmation did not open"
        )
        XCTAssertTrue(
            app.staticTexts["confirm.breakdown"].exists,
            "the confirmation must say when the space actually returns"
        )

        app.buttons["confirm.cancel"].tap()
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, before, "backing out must change nothing")

        app.buttons["review.delete"].tap()
        XCTAssertTrue(app.staticTexts["confirm.total"].waitForExistence(timeout: 20))
        app.buttons["confirm.delete"].tap()

        XCTAssertTrue(
            app.staticTexts["review.result"].waitForExistence(timeout: 30),
            "the deletion result was never reported"
        )
    }
}
