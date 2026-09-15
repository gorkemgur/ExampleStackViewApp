import XCTest

/// Rungs that were given space and never drawn.
///
/// This defect has now happened twice in the same screen, one nesting level apart, and both
/// times every test stayed green: they ask whether an element exists, and a rung that is never
/// built is simply never queried for. The first time it was a `LazyVStack` inside the list's own
/// `LazyVStack` swallowing a rung's rows. The second time the rungs *were* the lazy stack's
/// children, and it reserved one rung's height without building it — 237.9 points of empty
/// screen under the Photos heading, while the heading said the kind held four items and the
/// screen showed three.
///
/// So this test measures instead of asking. It is the only kind of test that can see this.
final class LadderDrawingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

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

    func testNoKindHeadingIsFollowedByEmptySpaceWhereARungShouldBe() {
        openReview()

        let window = app.windows.firstMatch.frame
        let heading = app.descendants(matching: .any)["review.kindsection.image"]

        // `exists` is true for an element far below the fold, and off screen an unbuilt row is
        // laziness working rather than a defect. Scroll until the heading is really in view.
        for _ in 0..<20 {
            if heading.exists && heading.frame.maxY < window.maxY - 200 { break }
            app.swipeUp()
        }
        XCTAssertTrue(heading.exists, "never reached the Photos heading")

        let first = app.staticTexts["review.section.image.1"]
        let second = app.staticTexts["review.section.image.2"]

        XCTAssertTrue(
            first.exists,
            "the Photos heading counts an item that belongs to the lower-quality re-sends rung, and that rung is not on screen"
        )
        XCTAssertTrue(second.exists)

        let gap = first.frame.minY - heading.frame.maxY
        XCTAssertLessThan(
            gap,
            40,
            "\(Int(gap)) points between the heading and the first rung: that is space reserved for something nobody drew"
        )
    }
}
