import XCTest

/// Walks the scan the way a person would, in a single pass: start it, watch it finish, read
/// what it found and what it deliberately left alone.
final class ScanUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testScanFindsTheFixtureDuplicatesRanksThemAndReportsWhatItSkipped() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "the scan entry point was never reachable")
        entry.tap()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20), "the scan screen did not open")
        XCTAssertFalse(app.buttons["scan.cancel"].exists, "cancel belongs to a running scan only")

        app.buttons["scan.start"].tap()

        XCTAssertTrue(
            app.staticTexts["scan.total"].waitForExistence(timeout: 60),
            "the scan never produced a total"
        )
        XCTAssertFalse(app.buttons["scan.cancel"].exists, "cancel must disappear once the scan is done")

        // Two byte-identical videos.
        XCTAssertTrue(app.staticTexts["scan.tier.0"].exists, "identical copies were not reported")
        // A messaging-app re-encode next to its full-size original — photo and video alike.
        XCTAssertTrue(app.staticTexts["scan.tier.1"].exists, "the inferior re-sends were not reported")
        // Burst frames, which must never be pre-ticked.
        XCTAssertTrue(app.staticTexts["scan.tier.2"].exists, "burst leftovers were not reported")

        let cloud = app.staticTexts["scan.cloud"]
        for _ in 0..<8 where !cloud.exists {
            app.swipeUp()
        }
        XCTAssertTrue(cloud.exists, "items left in iCloud must be reported, not silently skipped")
    }

    /// The screen's whole reason to exist as a separate step.
    ///
    /// The overview already carries a "Scan for duplicates" key, so if this screen only
    /// repeats it then it is chrome. It earns the tap by saying what is about to be opened
    /// before it is opened — and the numbers have to be there before the button is pressed,
    /// not after, which is what this asserts.
    func testTheScanScreenSaysWhatItIsAboutToOpenBeforeItOpensAnything() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20))

        let summary = require(
            "scan.plan.summary", in: app,
            "the scan screen never said how much of the library it would read"
        )
        guard summary.exists else { return }
        XCTAssertTrue(
            summary.label.contains("will be opened"),
            "the plan summary read \(summary.label)"
        )
        XCTAssertTrue(
            app.otherElements["scan.plan"].exists || app.staticTexts["scan.plan"].exists,
            "the per-kind ledger was not on the screen"
        )
        XCTAssertTrue(
            app.buttons["scan.start"].isHittable,
            "the ledger must not push the start key off the screen"
        )
    }
    /// The same control, on the other screen that matters, at the same text size.
    ///
    /// `ReachPicker` is shared, so the stacking fix reaches the strictness picker for free —
    /// and "for free" is exactly the claim that deserves a measurement. This screen is not the
    /// review screen: the picker sits on a dark slab inside a card, with an explanation
    /// underneath it, and a control that grows from 44pt tall to three rows of 65 has somewhere
    /// new to overflow. So this asks the two questions the review test cannot: are the steps
    /// stacked here too, and does the column still fit the width it was given.
    func testTheStrictnessPickerFitsTheSlabAtAccessibilitySizes() {
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            // The short spelling. The long one is not a constant the system knows, and it
            // fails by quietly leaving the app at an ordinary size.
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let entry = app.buttons["root.scan"]
        for _ in 0..<10 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "the scan entry point was never reachable")
        entry.tap()
        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20), "the scan screen did not open")

        let first = element("scan.strictness.0", in: app)
        for _ in 0..<10 where !first.exists {
            app.swipeUp()
        }
        guard first.waitForExistence(timeout: 15) else {
            XCTFail("the strictness picker was never reached. What was on the screen:\n\n\(screen(app))")
            return
        }
        let frames = (0..<3).map { element("scan.strictness.\($0)", in: app).frame }

        for index in 1..<frames.count {
            XCTAssertGreaterThanOrEqual(
                frames[index].minY,
                frames[index - 1].maxY,
                "at AX3XL the strictness picker is still a row: step \(index) starts at \(frames[index].minY) while step \(index - 1) ends at \(frames[index - 1].maxY)"
            )
        }

        // And it has to fit. A stacked step takes the whole row, and the row is inside a card
        // inside the slab's padding — if that arithmetic is wrong the label leaves the screen
        // rather than being scaled down, which is the trade this fix deliberately made.
        let window = app.windows.firstMatch.frame
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThanOrEqual(
                frame.minX,
                window.minX,
                "step \(index) starts at \(frame.minX), off the left of a \(window.width)pt window"
            )
            XCTAssertLessThanOrEqual(
                frame.maxX,
                window.maxX,
                "step \(index) ends at \(frame.maxX), past the right of a \(window.width)pt window"
            )
        }
    }

    /// The result cards have to fit the phone they are drawn on.
    ///
    /// `Badge` asks for its own width and will not give it back: `.fixedSize(horizontal: true,
    /// vertical: true)`, unconditionally. That was put there for a real reason — in the
    /// onboarding rung the pill was handed the leftovers of a row that had already spent its
    /// width and wrapped two words onto two cramped lines — but the remedy was written as an
    /// always. At an accessibility size the badge's two words are wide enough that the card
    /// cannot be drawn in 390 points, and a card that cannot be drawn is not scrolled to: it
    /// is clipped at both edges, so "Burst leftovers" is read as "leftovers" and "Your call"
    /// as "ur call".
    ///
    /// A vertical `ScrollView` does not rescue this. It scrolls the axis the card is not
    /// overflowing on.
    func testTheScanResultCardsFitTheScreenAtAccessibilitySizes() {
        runScan()
        let baselineText = require("scan.total", in: app, timeout: 30).frame.height

        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            // Short spelling only — see `testTheStrictnessPickerFitsTheSlabAtAccessibilitySizes`.
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        runScan()

        let grownText = require("scan.total", in: app, timeout: 30).frame.height
        XCTAssertGreaterThan(
            grownText,
            baselineText * 1.3,
            "the launch argument never reached the app: the scan total is \(grownText)pt at AX3XL "
            + "against \(baselineText)pt at the default size. Nothing below this line is about the cards."
        )

        let window = app.windows.firstMatch.frame
        for tier in 0..<3 {
            let title = app.staticTexts["scan.tier.\(tier)"]
            for _ in 0..<10 where !title.exists {
                app.swipeUp()
            }
            guard title.waitForExistence(timeout: 15) else {
                XCTFail("tier \(tier) was never reached. What was on the screen:\n\n\(screen(app))")
                return
            }
            let frame = title.frame
            XCTAssertGreaterThanOrEqual(
                frame.minX, window.minX,
                "tier \(tier)'s title starts at \(frame.minX), off the left of a \(window.width)pt window — "
                + "the card is wider than the phone, so its first characters are cut off"
            )
            XCTAssertLessThanOrEqual(
                frame.maxX, window.maxX,
                "tier \(tier)'s title ends at \(frame.maxX), past the right of a \(window.width)pt window"
            )

            // The title is a weak witness: it wraps inside its column and lands within a few
            // points of the edge either way. The bytes column is the element that actually
            // refuses to shrink, so it is the one that ends up furthest off the phone.
            let bytes = app.staticTexts["scan.tier.\(tier).bytes"]
            XCTAssertTrue(bytes.exists, "tier \(tier) has no bytes column")
            let bytesFrame = bytes.frame
            XCTAssertGreaterThanOrEqual(
                bytesFrame.minX, window.minX,
                "tier \(tier)'s bytes start at \(bytesFrame.minX), off the left of a \(window.width)pt window"
            )
            XCTAssertLessThanOrEqual(
                bytesFrame.maxX, window.maxX,
                "tier \(tier)'s bytes end at \(bytesFrame.maxX), past the right of a \(window.width)pt window — "
                + "the column will not give up its width, so the card is drawn wider than the phone"
            )
        }
    }

    private func runScan() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<10 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "the scan entry point was never reachable")
        entry.tap()

        let start = app.buttons["scan.start"]
        for _ in 0..<10 where !start.exists {
            app.swipeUp()
        }
        XCTAssertTrue(start.waitForExistence(timeout: 20), "the scan screen did not open")
        start.tap()
        XCTAssertTrue(
            app.staticTexts["scan.total"].waitForExistence(timeout: 60),
            "the scan never produced a total"
        )
    }
}

// MARK: - The strip

/// The scan, seen from a screen that is not the scan screen.
///
/// The scan became the app's rather than the screen's in the previous phase, which is what made
/// this possible *and* what made it necessary: backing out of the scan screen no longer kills
/// the scan, so without a strip there is a job running with nothing on screen to say so.
///
/// The scan is held before backing out rather than raced against. A twenty-eight item fixture
/// finishes in seconds, and a test that has to get off the screen before it does would be a
/// test of how fast the simulator is that day. A hold lasts until somebody lifts it — so what
/// is asserted below is the strip's behaviour, not the machine's timing. It also pins the claim
/// the previous phase made and never proved from outside: the scan is still there after you
/// leave the screen that started it.
final class ScanStripUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // `-slow-scan` is the whole reason this test can exist. See `AppEnvironment`: the
        // fixture scan is otherwise over before a query for its Pause key resolves, which
        // this test measured the hard way.
        app.launchArguments = ["-ui-testing", "-slow-scan"]
        app.launch()
    }

    func testAHeldScanIsReportedOnTheOverviewAndTheStripLeadsBackToIt() {
        let entry = app.buttons["root.scan"]
        for _ in 0..<8 where !entry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "the scan entry point was never reachable")
        entry.tap()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 20), "the scan screen did not open")
        app.buttons["scan.start"].tap()

        let hold = require("scan.pause", in: app, "a running scan offered no way to hold it")
        hold.tap()

        XCTAssertFalse(
            element("scan.strip", in: app).exists,
            "the strip must not draw over the scan screen, which is already showing this reading"
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let strip = require(
            "scan.strip", in: app,
            "a scan that is still running was not reported anywhere after leaving the scan screen"
        )
        XCTAssertEqual(
            strip.label, "Scan paused",
            "the hold is drawn as a tint and a glyph; VoiceOver gets neither unless the label says it"
        )

        strip.tap()

        XCTAssertTrue(
            element("scan.pause", in: app).waitForExistence(timeout: 10),
            "tapping the strip did not land back on the scan it was reporting"
        )
        XCTAssertFalse(
            element("scan.strip", in: app).exists,
            "the strip must go away again once you are looking at the scan itself"
        )

        // Leave nothing running behind this test.
        app.buttons["scan.cancel"].tap()
    }
}
