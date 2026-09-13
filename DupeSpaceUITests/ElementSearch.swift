import XCTest

/// Finding an element without guessing its type, and saying what was on the screen when it is
/// not there.
///
/// TWO LESSONS FROM ONE RUN, and I had already learned both elsewhere.
///
/// The first: `app.otherElements["budget.exhausted"]` found nothing, and the element was on the
/// screen. It carries `.accessibilityElement(children: .combine)`, and a combined element whose
/// children are all text is published as a *static text*, not a container — so the identifier
/// was right, the screen was right, and the query was looking in the wrong drawer. A test that
/// asserts an identifier is on screen has no business also asserting which XCUIElement bucket
/// the framework happened to file it under; that is an implementation detail of SwiftUI's
/// accessibility translation, and it moves. `element(_:)` searches every type at once.
///
/// The second: five UI tests failed for three runs and all any of them could say was
/// `XCTAssertTrue failed - no sort chip for biggest`. Which identifier was missing, and nothing
/// about what *was* there — so every round cost a full twenty-minute run to learn one fact. The
/// Python driver that walks this same app has dumped the whole element tree on failure since
/// the first time it cost me a round trip, and the test suite, which fails far more often, had
/// nothing. `require(_:)` prints the tree.
extension XCTestCase {

    /// An element with this identifier, whatever type the framework decided it is.
    ///
    /// One query, evaluated lazily, and I am putting it back to that after measuring the
    /// alternative. I changed this to try five typed queries first, on the reasoning that
    /// `descendants(matching: .any)` walks the whole tree and a typed query walks less of it.
    /// The run after that change took a UI shard past twenty-four minutes — longer than the
    /// entire unsharded suite had taken before it.
    ///
    /// The reasoning was wrong in the case that actually matters. Every caller is *waiting*
    /// for something that has not appeared yet, usually a frame after a tap. Resolving eagerly
    /// meant five full evaluations that all came back empty, and then a poll against the
    /// broadest query anyway. The lazy version hands `waitForExistence` one query and lets it
    /// poll that, which is what it is for.
    ///
    /// Measure before optimising, and measure after. I did neither.
    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Wait for an element, and print the whole screen if it never arrives.
    ///
    /// - Returns: the element, so a caller can go on to measure or tap it.
    @discardableResult
    func require(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 20,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let found = element(identifier, in: app)
        guard found.waitForExistence(timeout: timeout) else {
            XCTFail(
                """
                \(message.isEmpty ? "'\(identifier)' never appeared" : message) \
                — waited \(Int(timeout))s. What was on the screen:

                \(app.debugDescription)
                """,
                file: file, line: line
            )
            return found
        }
        return found
    }
}
