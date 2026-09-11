import XCTest

/// Drives the app against the deterministic stub library, so these assertions mean the same
/// thing on every runner and never wait on a permission alert nobody can tap.
final class LaunchUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testRootScreenAppears() {
        XCTAssertTrue(
            app.navigationBars["DupeSpace"].waitForExistence(timeout: 30),
            "app did not reach its root screen"
        )
    }

    func testStorageCardShowsACapacityReading() {
        XCTAssertTrue(
            app.staticTexts["storage.headline"].waitForExistence(timeout: 30),
            "no capacity reading was rendered"
        )
        XCTAssertTrue(
            app.staticTexts["storage.caveat"].exists,
            "the estimate caveat must stay visible next to the number it qualifies"
        )
    }

    func testAuthorisedLibraryShowsItsBreakdownAndNoPermissionWall() {
        XCTAssertTrue(
            app.staticTexts["breakdown.title"].waitForExistence(timeout: 30),
            "the category breakdown never appeared"
        )
        XCTAssertFalse(
            app.staticTexts["access.headline"].exists,
            "an authorised library must not show the permission wall"
        )
        XCTAssertFalse(app.buttons["access.button"].exists)
    }

    func testBreakdownListsTheCategoriesInTheFixture() {
        XCTAssertTrue(app.staticTexts["breakdown.title"].waitForExistence(timeout: 30))

        for identifier in ["breakdown.row.videos", "breakdown.row.screenshots", "breakdown.row.photos"] {
            XCTAssertTrue(
                app.staticTexts[identifier].exists,
                "\(identifier) missing from the breakdown"
            )
        }
    }

    func testLimitsCardIsAlwaysShown() {
        XCTAssertTrue(app.staticTexts["breakdown.title"].waitForExistence(timeout: 30))

        let limits = app.staticTexts["limits.title"]
        for _ in 0..<8 where !limits.exists {
            app.swipeUp()
        }
        XCTAssertTrue(limits.exists, "the honesty card must never be conditional")
    }

    func testScrollingReachesTheBiggestItemsCard() {
        XCTAssertTrue(app.staticTexts["breakdown.title"].waitForExistence(timeout: 30))

        let largest = app.staticTexts["largest.title"]
        for _ in 0..<8 where !largest.exists {
            app.swipeUp()
        }
        XCTAssertTrue(largest.exists, "the biggest-items card was never reachable by scrolling")
    }
}
