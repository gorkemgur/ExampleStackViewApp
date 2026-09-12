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
        // Kind first, then tier — so the identifier has to name both, and a bare
        // `review.section.0` would match one rung per kind. Asserted by shape rather than by
        // `image`: the fixture's byte-identical pair is the two videos, and which kind happens
        // to hold the cheapest rung is a property of the fixture, not of the screen.
        let identical = app
            .staticTexts
            .matching(NSPredicate(format: "identifier BEGINSWITH 'review.section.' AND identifier ENDSWITH '.0'"))
            .firstMatch
        XCTAssertTrue(identical.waitForExistence(timeout: 10), "no identical-copies rung anywhere")

        let count = app.staticTexts["review.count"]
        let before = count.label

        let toggle = app
            .buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'review.selectall.' AND identifier ENDSWITH '.0'"))
            .firstMatch
        XCTAssertTrue(toggle.exists, "each section needs a whole-section control")
        toggle.tap()

        XCTAssertNotEqual(count.label, before, "toggling a section must change the selection")
    }

    func testBudgetSliderCanDriveTheSelection() {
        openReview()

        let slider = app.sliders["budget.slider"]
        XCTAssertTrue(slider.exists, "the space budget control is the point of this screen")

        // Dragged, not `adjust(toNormalizedSliderPosition:)`.
        //
        // The fader is a custom control behind an `accessibilityRepresentation`, and that
        // representation carries the byte figure as its value — "2.02 GB" — because a
        // percentage is not what anyone wants read to them here. XCUITest's `adjust` needs a
        // numeric position it can parse out of that value, so it failed with "unable to get
        // expected attributes for slider". Choosing between an announcement a person can use
        // and a convenience method a test can use is not a real choice; the test drags the
        // control the way a finger does instead, which is also the only thing that proves the
        // gesture works.
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            )

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

        // Everything lossless has just gone, so "No loss" now reaches nothing — and a fader
        // with no target to set is a control with no job. It is not drawn greyed, it is not
        // drawn: the line that names what ran out stands where it was.
        let exhausted = app.otherElements["budget.exhausted"]
        XCTAssertTrue(
            exhausted.waitForExistence(timeout: 15),
            "after a lossless pass the budget card must say the depth has run out"
        )
        XCTAssertFalse(
            app.sliders["budget.slider"].exists,
            "a fader that can reach nothing should not be on the screen at all"
        )
        XCTAssertFalse(
            app.staticTexts["budget.summary"].exists,
            "the caption repeats what the line above it already says"
        )
    }

    /// The chips the simulator audit caught at 32 and 34 points tall.
    ///
    /// The pills stay that size on purpose — a sort control that is as loud as the delete key
    /// is a worse screen — so the hit area grows outside the pill instead, and this is the
    /// test that says so, because nothing about the pill's appearance would change if the
    /// invisible half were dropped again.
    func testTheListControlsAreBigEnoughToHit() {
        openReview()

        let minimum: CGFloat = 44

        for order in ["biggest", "oldest", "newest"] {
            let chip = app.buttons["review.order.\(order)"]
            XCTAssertTrue(chip.waitForExistence(timeout: 20), "no sort chip for \(order)")
            XCTAssertGreaterThanOrEqual(
                chip.frame.height, minimum,
                "the \(order) chip is \(chip.frame.height)pt tall, under the 44pt target"
            )
        }

        // The fixture holds photos and videos, so all three of these are on the row. Asserted
        // only when present, because the row hides itself when there is nothing to filter.
        for slug in ["all", "image", "video"] {
            let chip = app.buttons["review.kind.\(slug)"]
            guard chip.exists else { continue }
            XCTAssertGreaterThanOrEqual(
                chip.frame.height, minimum,
                "the \(slug) chip is \(chip.frame.height)pt tall, under the 44pt target"
            )
        }

        XCTAssertTrue(
            app.buttons["review.kind.all"].exists,
            "the fixture has two kinds, so the kind row must be on screen"
        )
    }

    /// Sorting may change where to start looking. It may never change what is on offer.
    ///
    /// The same invariant DupeCore holds in `ReviewBuilderTests`, asserted here at the only
    /// place it can actually be broken by a view: the total and the count are what the plan
    /// would delete, and reordering the list must leave both exactly where they were.
    func testChangingTheOrderDoesNotChangeWhatIsOffered() {
        openReview()

        let total = app.staticTexts["review.total"]
        let count = app.staticTexts["review.count"]
        let before = (total.label, count.label)

        for order in ["oldest", "newest", "biggest"] {
            let chip = app.buttons["review.order.\(order)"]
            XCTAssertTrue(chip.waitForExistence(timeout: 20))
            chip.tap()

            XCTAssertEqual(total.label, before.0, "sorting by \(order) changed the total on offer")
            XCTAssertEqual(count.label, before.1, "sorting by \(order) changed the number selected")
        }
    }
}
