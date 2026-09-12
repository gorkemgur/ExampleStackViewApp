import XCTest

/// Drives the app against the deterministic stub library, so these assertions mean the same
/// thing on every runner and never wait on a permission alert nobody can tap.
///
/// Each test costs a fresh app launch, so they are written to cover a whole screen rather than
/// one element apiece: a suite that relaunches twenty times spends longer fighting the
/// simulator than it does testing.
final class LaunchUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testRootScreenShowsCapacityWithItsCaveat() {
        XCTAssertTrue(
            app.navigationBars["DupeSpace"].waitForExistence(timeout: 30),
            "app did not reach its root screen"
        )
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

        for identifier in ["breakdown.row.videos", "breakdown.row.screenshots", "breakdown.row.photos"] {
            XCTAssertTrue(app.staticTexts[identifier].exists, "\(identifier) missing from the breakdown")
        }

        XCTAssertFalse(
            app.staticTexts["access.headline"].exists,
            "an authorised library must not show the permission wall"
        )
        XCTAssertFalse(app.buttons["access.button"].exists)
    }

    /// One scroll to the bottom, checking everything that lives below the fold on the way.
    func testEverythingBelowTheFoldIsReachable() {
        XCTAssertTrue(app.staticTexts["breakdown.title"].waitForExistence(timeout: 30))

        let folders = app.buttons["folders.add"]
        let largest = app.staticTexts["largest.title"]
        let limits = app.staticTexts["limits.title"]

        for _ in 0..<10 where !(folders.exists && largest.exists && limits.exists) {
            app.swipeUp()
        }

        XCTAssertTrue(folders.exists, "there must be a way to hand over a folder")
        XCTAssertTrue(
            app.staticTexts["folders.empty"].exists,
            "with no folders granted the card should say so rather than look broken"
        )
        XCTAssertTrue(largest.exists, "the biggest-items card was never reachable by scrolling")
        XCTAssertTrue(limits.exists, "the honesty card must never be conditional")
    }
}
