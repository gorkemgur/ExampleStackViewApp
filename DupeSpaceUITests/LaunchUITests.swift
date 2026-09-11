import XCTest

final class LaunchUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsStorage() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.navigationBars["DupeSpace"].waitForExistence(timeout: 20),
            "app did not reach its root screen"
        )

        let headline = app.staticTexts["storage.headline"]
        let unavailable = app.staticTexts["storage.unavailable"]
        XCTAssertTrue(
            headline.waitForExistence(timeout: 10) || unavailable.exists,
            "neither a capacity reading nor its fallback was shown"
        )
    }
}
