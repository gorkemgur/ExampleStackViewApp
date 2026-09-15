import XCTest

/// What the screen behind the onboarding cover looks like once the cover goes away.
///
/// Written because a real phone showed the overview collapsed into a column about a fifth of
/// the window wide, with the access card's copy wrapping one word per line — and the simulator
/// looked perfect, because nothing had ever dismissed the cover and photographed what was
/// underneath. A screenshot of a modal proves nothing about its presenter.
final class OnboardingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        // `-onboarding` alongside `-ui-testing`: the fixtures stay, and the cover comes back.
        app.launchArguments = ["-ui-testing", "-onboarding"]
        app.launch()
        return app
    }

    /// The state a real phone is actually in after a fresh install, which no other test covers.
    ///
    /// Every other UI test runs behind `-ui-testing`, which pins `StubMediaLibrary(.authorized)`
    /// — so `AccessCardView` is never drawn, and it is `AccessCardView` that came back 91pt wide
    /// on the device. No `-ui-testing` here: real PhotoKit, permission unanswered, the card on
    /// screen.
    ///
    /// Three flags, and every one of them replaces a piece of simulator state this test used to
    /// take on faith. It launched with no arguments at all, and so depended on two things it did
    /// not establish: `hasSeenOnboarding` being false — true exactly once per simulator, because
    /// the first test here that taps Skip writes it and it survives every reinstall — and the
    /// photo permission being unanswered, true until anything answers it, after which
    /// `AccessCardView` is never drawn at all. It passed on a fresh simulator and failed on
    /// every run after, with messages that blamed the app for state the suite had left behind.
    /// Both were reproduced and then measured: the flag read `true` in the container's plist,
    /// and `simctl privacy reset photos` turned the second failure green without touching a line
    /// of code.
    ///
    /// `-onboarding` beats the store, `-unanswered-access` puts the stub at `.notDetermined` so
    /// the card is on screen, and the card is drawn by the same view either way — which is the
    /// whole of what this test measures.
    func testTheAccessCardIsFullWidthAfterTheCoverIsDismissed() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-onboarding", "-unanswered-access"]
        app.launch()

        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "onboarding did not present on a clean install")
        skip.tap()

        let headline = app.staticTexts["access.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 10), "the access card was not drawn")

        if let data = XCUIScreen.main.screenshot().pngRepresentation as Data? {
            try? data.write(to: URL(fileURLWithPath: "/tmp/dupespace-access-card.png"))
        }

        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(
            headline.frame.width,
            window.width * 0.6,
            "the access card collapsed: \(Int(headline.frame.width))pt in a \(Int(window.width))pt window"
        )
    }

    /// The user reported that the pages only move by button, never by finger.
    func testThePagesCanBeTurnedByDragging() {
        let app = launched()
        let title = app.staticTexts["onboarding.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let first = title.label

        app.swipeLeft()

        let changed = NSPredicate(format: "label != %@", first)
        expectation(for: changed, evaluatedWith: app.staticTexts["onboarding.title"])
        waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error, "a left swipe did not turn the page — it is still '\(first)'")
        }
    }

    func testTheOnboardingCoverIsPresentedOnAForcedLaunch() {
        let app = launched()
        XCTAssertTrue(
            app.staticTexts["onboarding.title"].waitForExistence(timeout: 10),
            "-onboarding did not bring the cover back"
        )
    }

    /// The regression this file exists for.
    func testTheOverviewIsFullWidthAfterTheCoverIsDismissed() {
        let app = launched()
        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()

        // A control whose style claims the full width — `keyQuiet` is a `KeyButtonStyle` with
        // `expands: true`, so if this is narrow the stack it sits in is narrow. Measuring an
        // arbitrary `staticTexts.firstMatch` measured a card *title*, which is short by design
        // and proves nothing either way.
        let key = app.buttons["root.livesurfaces"]
        XCTAssertTrue(key.waitForExistence(timeout: 10), "nothing was on the overview to measure")

        if let data = XCUIScreen.main.screenshot().pngRepresentation as Data? {
            try? data.write(to: URL(fileURLWithPath: "/tmp/dupespace-after-onboarding.png"))
        }

        let window = app.windows.firstMatch.frame
        let content = key.frame
        // Generous: the content is inset 16pt each side, so anything near the window width
        // passes and the observed failure — a fifth of the window — is nowhere close.
        XCTAssertGreaterThan(
            content.width,
            window.width * 0.6,
            "the overview collapsed: control is \(Int(content.width))pt in a \(Int(window.width))pt window"
        )
    }
}
