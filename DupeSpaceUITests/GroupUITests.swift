import XCTest

/// Overruling the engine, which is the promise the whole product rests on: the app's pick is a
/// default, and defaults can be wrong about someone else's photographs.
final class GroupUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    /// By label, and in every drawer rather than only `buttons`.
    ///
    /// A `confirmationDialog`'s buttons carry no identifiers, and the subscript form searches
    /// identifiers first — which is why tapping "Cancel" could not find a button that was
    /// plainly on screen. That was the first version of this. The second failed too, and said
    /// why in a way worth keeping:
    ///
    ///     Failed to tap Button (First Match): No matches found ... 'label == "Cancel"'
    ///     Automation type mismatch: computed Button from legacy attributes vs
    ///     DisclosureTriangle from modern attribute
    ///
    /// The framework and the app disagree about what type that element is, so `app.buttons`
    /// misses it from one side while the screenshot shows it from the other. A label is a
    /// label; which bucket the accessibility translation filed it under is not this test's
    /// business.
    ///
    /// A method rather than a local closure: a closure here captures `app` off `self`, and
    /// XCTest's `self` in a test body is not implicitly capturable.
    private func button(labelled text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    /// Tap something by its label, and print the screen if it is not there.
    private func tap(
        labelled text: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = button(labelled: text)
        guard target.waitForExistence(timeout: timeout) else {
            XCTFail(
                "nothing labelled '\(text)' appeared in \(Int(timeout))s. What was on the screen:\n\n\(screen(app))",
                file: file, line: line
            )
            return
        }
        target.tap()
    }

    /// Scan the fixture and land on the review screen.
    private func openReview() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20))
        app.buttons["scan.start"].tap()

        let review = app.buttons["scan.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 60))
        review.tap()
        XCTAssertTrue(app.staticTexts["review.total"].waitForExistence(timeout: 20))
    }

    private func openFirstGroup() {
        openReview()

        // The link half of the row, not the tick box beside it: the box selects the whole
        // group, and a test that taps and hopes is a test that toggles a deletion by accident.
        let row = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'review.open.'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no group row to open")

        // And then make sure the touch actually reaches it.
        //
        // `ReviewView` draws its dock through `safeAreaInset(edge: .bottom)` as a floating
        // panel the list scrolls *under* — deliberately, and it says so at `ReviewView.swift:786`.
        // At the scroll position this test arrives at, the first group row is entirely beneath
        // it: the row measured {{87, 713}, {287, 72}} with the dock's own key at
        // {{209, 758}, {163, 52}} and the panel reaching about fifty points higher again. So
        // `tap()` sent the touch into the dock, armed the plan, opened the confirmation sheet —
        // and the test then failed two lines later saying the group screen had no survivor on
        // it, which was true, because the group screen had never been opened.
        //
        // `isHittable` is not the guard for this. It answered *true* for a row that was covered
        // end to end, which is why asking it fixed nothing. Geometry is the guard: scroll until
        // the row clears the dock, and refuse to tap if it never does.
        let dockKey = app.buttons["review.delete"]
        var scrolls = 0
        while dockKey.exists, row.frame.maxY > dockKey.frame.minY - 64, scrolls < 8 {
            app.swipeUp()
            scrolls += 1
        }
        if dockKey.exists {
            XCTAssertLessThan(
                row.frame.maxY,
                dockKey.frame.minY - 64,
                "the group row never came out from under the floating dock"
            )
        }
        row.tap()
    }

    /// The card for one copy has to fit the phone it is drawn on.
    ///
    /// Under the comparator sit two badges and a button in one row. The badges ask for their
    /// own width and will not give it back — `Badge` is `fixedSize` for a reason recorded in
    /// `DesignSystem.swift` — and at AX5 the two of them alone are 369 points of a card that
    /// has 300 inside its padding. The button between them is the only thing in the row that
    /// *can* shrink, so it does, to 79 points, and "Where they differ" wraps letter by letter
    /// into a capsule 720 points tall. The card itself comes out at 464 and is clipped at both
    /// edges: "Keeping" reads "eeping", "This copy" reads "This cop", and the tick box at the
    /// head of the row — the control that decides whether this copy is deleted — is off the
    /// left of the screen entirely.
    ///
    /// The outer stack is lazy, so it does not re-propose the widest child's width to the
    /// others the way `ScanView`'s eager one does; only this card overflows, and the survivor
    /// panel above it stays put. That is why the assertions are on the card's own parts.
    func testTheCopyCardFitsTheScreenAtAccessibilitySizes() {
        openReview()
        let baselineText = app.staticTexts["review.total"].frame.height

        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            // Short spelling only — the long form is ignored without a word. See
            // `ScanUITests.testTheStrictnessPickerFitsTheSlabAtAccessibilitySizes`.
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        openReview()

        let grownText = app.staticTexts["review.total"].frame.height
        XCTAssertGreaterThan(
            grownText,
            baselineText * 1.3,
            "the launch argument never reached the app: the review total is \(grownText)pt at AX5 "
            + "against \(baselineText)pt at the default size. Nothing below this line is about the card."
        )

        // Straight to the row. At this size `app.swipeUp()` does not move the review list at
        // all — forty swipes left the first group row where it started — so the geometry guard
        // `openFirstGroup` uses can never be satisfied here. The tap itself scrolls the row in.
        let row = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'review.open.'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no group row to open")
        row.tap()
        XCTAssertTrue(
            app.staticTexts["group.keeper"].waitForExistence(timeout: 10),
            "the group screen did not open. What was on the screen:\n\n\(screen(app))"
        )

        let window = app.windows.firstMatch.frame
        let keeping = app.staticTexts["Keeping"].firstMatch
        for _ in 0..<10 where !keeping.exists { app.swipeUp() }
        XCTAssertTrue(keeping.waitForExistence(timeout: 10), "the comparator never appeared")

        let candidate = app
            .descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH 'candidate.' AND NOT identifier CONTAINS '.difference.' "
                    + "AND NOT identifier CONTAINS '.table.' AND NOT identifier CONTAINS '.keep.'"
            ))
            .firstMatch
        XCTAssertTrue(candidate.exists, "no copy row on the group screen")
        let rowFrame = candidate.frame
        XCTAssertGreaterThanOrEqual(
            rowFrame.minX, window.minX,
            "the copy row starts at \(rowFrame.minX), off the left of a \(window.width)pt window — "
            + "the tick box at its head cannot be seen or tapped"
        )
        XCTAssertLessThanOrEqual(
            rowFrame.maxX, window.maxX,
            "the copy row ends at \(rowFrame.maxX), past the right of a \(window.width)pt window"
        )

        for label in ["Keeping", "This copy"] {
            let chip = app.staticTexts[label].firstMatch
            let frame = chip.frame
            XCTAssertGreaterThanOrEqual(
                frame.minX, window.minX,
                "'\(label)' starts at \(frame.minX), off the left of the window — its first letters are cut"
            )
            XCTAssertLessThanOrEqual(
                frame.maxX, window.maxX,
                "'\(label)' ends at \(frame.maxX), past the right of the window — its last letters are cut"
            )
        }

        let toggle = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'candidate.difference.'"))
            .firstMatch
        XCTAssertTrue(toggle.exists, "the difference toggle never appeared")
        let pill = toggle.frame
        XCTAssertGreaterThan(
            pill.width, pill.height,
            "the difference toggle is \(pill.width) wide and \(pill.height) tall: a pill squeezed into a "
            + "column, its label wrapping letter by letter"
        )
        // And not the opposite failure. "Where they differ" at this size is wider than the card,
        // so it has to take two lines; a pill one line tall has cut the label to "Where the…".
        // XCUITest cannot see an ellipsis, but it can see a height: one line of this type is
        // the height of a badge beside it.
        let oneLine = keeping.frame.height
        XCTAssertGreaterThan(
            pill.height, oneLine * 1.5,
            "the difference toggle is \(pill.height)pt tall against \(oneLine)pt for one line of the "
            + "same type: its label was cut to one line instead of wrapping"
        )
    }

    func testTheGroupScreenShowsWhatStaysAndWhyEachCopyIsOffered() {
        openFirstGroup()

        XCTAssertTrue(app.staticTexts["group.keeper"].waitForExistence(timeout: 10), "the survivor has to be named")
        XCTAssertTrue(app.buttons["group.selectall"].exists, "a sixty-copy burst needs a bulk control")
        XCTAssertTrue(app.buttons["group.deleteall"].exists, "the one way to say you want none of them")
    }

    /// The awkward control stays awkward. Tapping it may not select anything on its own — it
    /// arms a confirmation, and the destructive key is still a screen away.
    func testDeletingAWholeGroupIsBehindAConfirmation() {
        openFirstGroup()

        let deleteAll = app.buttons["group.deleteall"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 10))
        deleteAll.tap()

        let arm = button(labelled: "Select them all")
        XCTAssertTrue(arm.waitForExistence(timeout: 10), "clearing a group must ask first")

        // Backing out, and not by the button. `confirmationDialog` is given a
        // `Button("Cancel", role: .cancel)` in `GroupDetailView` and that button is not in the
        // element tree: the dialog comes back as a `Sheet` holding its title, its message and
        // `Select them all`, and nothing else. The system owns the cancel affordance and does
        // not publish it where a query can reach.
        //
        // So this backs out the way a person would when they change their mind — a tap on the
        // screen above the sheet — and then *checks that the sheet actually went away*, which
        // is the part the old version took on trust.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()

        let dialog = button(labelled: "Select them all")
        XCTAssertTrue(
            dialog.waitForNonExistence(timeout: 10),
            "the confirmation is still up after backing out of it:\n\n\(screen(app))"
        )
        XCTAssertFalse(app.buttons["group.keepone"].exists, "cancelling must not arm anything")
    }

    /// Two controls on this screen a finger has to find.
    ///
    /// Both were drawn at the height the *pill* wants to be rather than the height a thumb
    /// needs. `group.selectall` at 34pt ticks every copy in the group — up to sixty of them.
    /// The difference toggle at 32pt is the more instructive of the two: it carries a
    /// `.contentShape(Capsule())`, which reads like the fix and does the opposite. A content
    /// shape *confines* the touch to the shape it is handed; it cannot make the target taller
    /// than the frame underneath it. A hit shape is not a hit size, and only a measurement
    /// tells those two apart.
    ///
    /// `ReviewView` already answered this on its sort and kind chips: the pill stays 34 and a
    /// 44pt frame is placed around it, so the hit area grows outside the pill rather than the
    /// pill growing to meet the finger. This holds the group screen to the same rule.
    func testTheControlsOnTheGroupScreenAreAFullFingerTall() {
        openFirstGroup()

        let selectAll = require("group.selectall", in: app, timeout: 15)
        XCTAssertGreaterThanOrEqual(
            selectAll.frame.height,
            44,
            "the control that ticks every copy in the group is \(selectAll.frame.height)pt tall"
        )

        // The toggle sits under a candidate's wipe, and the candidates are a `LazyVStack`:
        // below the fold it is not built, so a query that does not scroll is asking about a
        // view that does not exist yet.
        let toggle = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'candidate.difference.'"))
            .firstMatch
        for _ in 0..<10 where !toggle.exists {
            app.swipeUp()
        }
        guard toggle.waitForExistence(timeout: 10) else {
            XCTFail("no difference toggle on the group screen. What was on it:\n\n\(screen(app))")
            return
        }
        XCTAssertGreaterThanOrEqual(
            toggle.frame.height,
            44,
            "the difference toggle is \(toggle.frame.height)pt tall"
        )
    }
}
