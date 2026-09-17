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

    /// The legend under the bar has one column per part on the disk, and each was its own
    /// `VStack`: at the default size both titles fit one line and nobody noticed the columns
    /// disagreed on height. At AX5 "Everything else" wraps to two lines while "Free" — four
    /// letters — stays on one, and because the two columns never shared a row, the byte figure
    /// under "Everything else" sat lower than the one under "Free": the same misalignment
    /// `copiesHeader`'s two independent counts had.
    func testTheLegendFiguresStayInARowEvenWhenOneTitleWrapsAndTheOtherDoesNot() {
        XCTAssertTrue(app.staticTexts["storage.headline"].waitForExistence(timeout: 30))
        let baselineTitle = app.staticTexts["storage.legend.other.title"].frame.height

        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["storage.headline"].waitForExistence(timeout: 30))

        let otherTitle = app.staticTexts["storage.legend.other.title"]
        let freeTitle = app.staticTexts["storage.legend.free.title"]
        XCTAssertTrue(otherTitle.waitForExistence(timeout: 10), "no 'Everything else' legend column")
        XCTAssertTrue(freeTitle.exists, "no 'Free' legend column")

        let grownTitle = otherTitle.frame.height
        XCTAssertGreaterThan(
            grownTitle, baselineTitle * 1.3,
            "the launch argument never reached the app: 'Everything else' is \(grownTitle)pt tall at "
            + "AX5 against \(baselineTitle)pt at the default size"
        )
        XCTAssertGreaterThan(
            grownTitle, freeTitle.frame.height * 1.3,
            "'Everything else' (\(grownTitle)pt) and 'Free' (\(freeTitle.frame.height)pt) wrapped to "
            + "the same number of lines: nothing below this line is about the misalignment two "
            + "different line counts cause"
        )

        let otherBytes = app.staticTexts["storage.legend.other.bytes"]
        let freeBytes = app.staticTexts["storage.legend.free.bytes"]
        XCTAssertTrue(otherBytes.exists, "no byte figure under 'Everything else'")
        XCTAssertTrue(freeBytes.exists, "no byte figure under 'Free'")

        XCTAssertEqual(
            otherBytes.frame.minY, freeBytes.frame.minY, accuracy: 2,
            "the byte figures sit \(otherBytes.frame.minY)pt and \(freeBytes.frame.minY)pt down the "
            + "screen: 'Everything else' wrapping to two lines pushed its own column's figure down "
            + "while 'Free', staying on one line, did not move"
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

    /// The Live Activity and the widget both link here. A link that opens the app and then
    /// leaves you on whatever screen you left is worse than no link at all.
    func testTheScanLinkOpensTheScanScreen() {
        XCTAssertTrue(app.staticTexts["storage.headline"].waitForExistence(timeout: 30))

        // The system opens it, exactly as the Lock Screen would: this exercises the real
        // scheme registration, not an internal shortcut.
        XCUIDevice.shared.system.open(URL(string: "dupespace://scan")!)

        XCTAssertTrue(
            app.buttons["scan.start"].waitForExistence(timeout: 20),
            "the scan link did not reach the scan screen"
        )
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

    /// The one picture anyone gets of the Live Activity.
    ///
    /// No simulator will show a Live Activity, so the app renders the same Lock Screen and
    /// Dynamic Island views on a screen of its own under `-ui-testing`, and the site's
    /// screenshot of them comes from a script that walks the app with idb. That script kept
    /// failing to open this sheet — idb reports elements a scroll view has scrolled past the
    /// bottom of the glass, so it tapped a coordinate the screen did not have. XCUITest does
    /// not have that hole, which makes this the right place to hold the door open.
    func testTheLiveSurfacesPreviewOpens() {
        XCTAssertTrue(app.staticTexts["breakdown.title"].waitForExistence(timeout: 30))

        let entry = app.buttons["root.livesurfaces"]
        for _ in 0..<10 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.exists, "the live surfaces entry was never reachable by scrolling")

        entry.tap()
        XCTAssertTrue(
            app.buttons["livepreview.close"].waitForExistence(timeout: 20),
            "tapping the entry did not present the preview"
        )

        app.buttons["livepreview.close"].tap()
        XCTAssertTrue(
            app.buttons["livepreview.close"].waitForNonExistence(timeout: 10),
            "the preview would not close"
        )
    }
}
