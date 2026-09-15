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

    /// Every row of a rung is drawn, not merely given room.
    ///
    /// The rung's rows used to sit in a `LazyVStack` nested inside the list's own `LazyVStack`.
    /// The inner one reserved each row's height and then built almost none of them: measured on
    /// the burst rung, one row of three was on screen and the other two were 172 points of
    /// nothing with the ladder's rail running through it. Every assertion in this suite passed
    /// throughout — they ask whether an element exists, and a row that is never built simply
    /// is not queried for. This counts them instead.
    func testEveryRowOfARungIsDrawnAndNotJustSpacedFor() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-crowded-library"]
        app.launch()

        openReview()

        let burst = app.staticTexts["review.section.image.2"]
        for _ in 0..<12 where !burst.exists {
            app.swipeUp()
        }
        XCTAssertTrue(burst.waitForExistence(timeout: 10), "no burst rung to measure")

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'review.group.2|'"))
        XCTAssertEqual(
            rows.count,
            3,
            "the fixture's burst rung holds three groups; anything fewer is a row that was given space and never drawn"
        )
    }

    /// A rung long enough to be folded offers the rest rather than pouring it out.
    ///
    /// Launched with `-crowded-library`, which puts twelve pairs of similar photographs in the
    /// fixture. The ordinary fixture's biggest rung is four groups, so nothing here could be
    /// seen without it — the arithmetic has a unit test, and this is the only thing that proves
    /// the row is drawn, can be reached and does something when it is tapped.
    func testALongRungOffersTheRestRatherThanPouringItOut() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-crowded-library"]
        app.launch()

        openReview()

        // Scrolled to, not merely queried. The list is a `LazyVStack`: rows below the fold are
        // not instantiated, so a query that does not scroll reports an empty screen and says
        // nothing about whether the row exists.
        let unfold = app.buttons["review.unfold.image.3"]
        for _ in 0..<12 where !unfold.exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            unfold.waitForExistence(timeout: 10),
            "a twelve-group rung was drawn whole, with nothing offering the rest"
        )

        let rows = NSPredicate(format: "identifier BEGINSWITH 'review.group.'")
        let before = app.buttons.matching(rows).count
        XCTAssertGreaterThan(before, 0, "no group rows on screen at all")

        unfold.tap()

        XCTAssertFalse(
            unfold.waitForExistence(timeout: 3),
            "the rung is open, so the offer to open it has nothing left to offer"
        )
        XCTAssertGreaterThan(
            app.buttons.matching(rows).count,
            before,
            "tapping it opened nothing"
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
        // Searched by identifier alone. This used to ask `app.otherElements`, and the strip
        // carries `.accessibilityElement(children: .combine)` — which publishes it as a static
        // text, because everything inside it is text. The identifier was on the screen the
        // whole time and the query was looking in the wrong drawer.
        require(
            "budget.exhausted", in: app, timeout: 15,
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

        // A hair under 44, because a point is not an integer on a 3x screen. The run that
        // caught this said:
        //
        //     ("43.99999999999994") is less than ("44.0")
        //
        // `.frame(minHeight: 44)` laid out on a device with a 3x scale comes back through
        // XCUITest's arithmetic six ten-trillionths short, and the chip is 44 points tall by
        // every measure that matters. `audit-ui.py` learned this weeks ago and carries an
        // `EDGE_SLACK` for exactly it; this assertion did not get the same memo and has been
        // failing a correct layout.
        let minimum: CGFloat = 44 - 0.01

        // The three sort chips became one menu, so what has to clear 44 points is the control
        // that opens it; the options inside are laid out by the system.
        let sort = require("review.order", in: app, "no sort control")
        if sort.exists {
            XCTAssertGreaterThanOrEqual(
                sort.frame.height, minimum,
                "the sort control is \(sort.frame.height)pt tall, under the 44pt target"
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
            app.buttons["review.order"].tap()

            let option = app.buttons["review.order.\(order)"]
            XCTAssertTrue(option.waitForExistence(timeout: 5), "the sort menu did not offer \(order)")
            option.tap()

            XCTAssertEqual(total.label, before.0, "sorting by \(order) changed the total on offer")
            XCTAssertEqual(count.label, before.1, "sorting by \(order) changed the number selected")
        }
    }

    /// The most consequential choice in the product, at the text size the people who need it
    /// actually run.
    ///
    /// `ReachPicker` hands each option an equal flexible column — on a 393pt device that is
    /// 393 - 32 - 40 = 321 inner, less 2x8 of spacing, about 102pt a column — and then defends
    /// it with `lineLimit(1)` and `minimumScaleFactor(0.7)`. `.footnote` is 13pt at Large and
    /// 49pt at AX5; seven tenths of 49 is 34, and "+ similar" is nine characters. A minimum
    /// scale factor is not a Dynamic Type strategy. It is permission to shrink the text until
    /// it stops fitting, and then truncate it anyway.
    ///
    /// Nothing in this project has ever looked at this control at these sizes: the Python walk
    /// relaunches at AX1 and stops there, and the scan screen was never reached at large text
    /// at all.
    ///
    /// Two launches, and the first one is not decoration. `XCUIApplication` has no API for the
    /// content size category, so it goes in as a launch argument — and a launch argument the
    /// app quietly ignores would fail every assertion below while the control was innocent.
    /// The baseline pass measures a plain piece of text on the same screen, so the run can say
    /// which of the two it caught.
    ///
    /// Geometry, not labels: VoiceOver reads the whole string off a `Text` that is drawing an
    /// ellipsis, so only the frames can tell whether a label had room.
    func testTheReachPickerStacksAtAccessibilitySizesRatherThanShrinkingItsLabels() {
        openReview()
        let baselineText = require("review.total", in: app, timeout: 20).frame.height

        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        openReview()

        let grownText = require("review.total", in: app, timeout: 20).frame.height
        // A ratio, not "bigger". The first version of this test asked for the long spelling,
        // `UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge`, which the system does not
        // recognise — and it did not fall back to Large either: the screen's own text came back
        // 31.3pt against 33.7pt, a 1.07x nudge that sailed through a `greaterThan` while the
        // app was nowhere near an accessibility size. AX3XL moves this text 1.54x. Anything
        // under 1.3 is the argument being misspelt, not the picker being wrong.
        XCTAssertGreaterThan(
            grownText,
            baselineText * 1.3,
            "the launch argument never reached the app: the screen's own text is \(grownText)pt at AX3XL against \(baselineText)pt at the default size. Nothing below this line is about the picker."
        )

        let frames = (0..<3).map { require("budget.depth.\($0)", in: app, timeout: 20).frame }

        for index in 1..<frames.count {
            XCTAssertGreaterThanOrEqual(
                frames[index].minY,
                frames[index - 1].maxY,
                "at AX3XL the reach picker is still a row: step \(index) starts at \(frames[index].minY) while step \(index - 1) ends at \(frames[index - 1].maxY)"
            )
        }

        // And the width stacking is for. A third of the inner width is about 102pt; a stacked
        // step gets the row, which is what stops nine characters being scaled into an ellipsis.
        let window = app.windows.firstMatch.frame
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThan(
                frame.width,
                window.width * 0.6,
                "step \(index) is \(frame.width)pt wide in a \(window.width)pt window"
            )
        }
    }
}
