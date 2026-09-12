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

    /// The live surfaces render nowhere a simulator can reach, so the app draws them on a
    /// screen of its own under test. This proves that screen renders every phase — the walk
    /// that photographs it cannot tell a laid-out view from a blank one.
    func testEveryLiveScanPhaseRenders() {
        let entry = app.buttons["root.livesurfaces"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "no way in to the live surfaces")
        entry.tap()

        XCTAssertTrue(
            app.buttons["livepreview.close"].waitForExistence(timeout: 10),
            "the live surfaces screen never appeared"
        )

        for headline in ["Scanning", "Paused", "Found space", "All clean", "Stopped"] {
            XCTAssertTrue(
                app.staticTexts[headline].exists,
                "the \(headline) state is not rendered"
            )
        }

        // The one thing that must never appear on a surface read without the app in front of
        // you: a claim that something was removed.
        XCTAssertTrue(app.staticTexts["Nothing was deleted"].exists)

        app.buttons["livepreview.close"].tap()
        XCTAssertTrue(app.navigationBars["DupeSpace"].waitForExistence(timeout: 10))
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
