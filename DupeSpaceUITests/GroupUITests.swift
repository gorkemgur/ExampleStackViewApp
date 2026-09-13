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
                "nothing labelled '\(text)' appeared in \(Int(timeout))s. What was on the screen:\n\n\(app.debugDescription)",
                file: file, line: line
            )
            return
        }
        target.tap()
    }

    private func openFirstGroup() {
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

        // The link half of the row, not the tick box beside it: the box selects the whole
        // group, and a test that taps and hopes is a test that toggles a deletion by accident.
        let row = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'review.open.'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no group row to open")
        row.tap()
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

        tap(labelled: "Cancel")
        XCTAssertFalse(app.buttons["group.keepone"].exists, "cancelling must not arm anything")
    }
}
