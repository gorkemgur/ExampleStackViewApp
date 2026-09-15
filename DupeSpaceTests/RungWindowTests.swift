import XCTest
import DupeCore
@testable import DupeSpace

/// How much of a rung is drawn.
final class RungWindowTests: XCTestCase {

    func testAShortRungIsDrawnWhole() {
        let state = RungWindow.state(groupCount: 3, isExpanded: false)

        XCTAssertEqual(state.shown, 3)
        XCTAssertEqual(state.hidden, 0)
        XCTAssertFalse(state.isTruncated, "there is nothing to fold away and no footer to draw")
    }

    func testALongRungStopsAtTheLimit() {
        let state = RungWindow.state(groupCount: 147, isExpanded: false)

        XCTAssertEqual(state.shown, RungWindow.limit)
        XCTAssertEqual(state.hidden, 142)
        XCTAssertTrue(state.isTruncated)
    }

    func testOneGroupOverTheLimitIsNotWorthHiding() {
        let state = RungWindow.state(groupCount: RungWindow.limit + 1, isExpanded: false)

        XCTAssertEqual(
            state.shown,
            RungWindow.limit + 1,
            "folding one row away to make room for a line that says one row was folded away is a worse screen than the row"
        )
        XCTAssertEqual(state.hidden, 0)
    }

    func testTwoGroupsOverTheLimitIsWorthHiding() {
        let state = RungWindow.state(groupCount: RungWindow.limit + 2, isExpanded: false)

        XCTAssertEqual(state.shown, RungWindow.limit)
        XCTAssertEqual(state.hidden, 2)
    }

    func testAnOpenedRungHidesNothing() {
        let state = RungWindow.state(groupCount: 147, isExpanded: true)

        XCTAssertEqual(state.shown, 147)
        XCTAssertEqual(state.hidden, 0, "the reader asked to see them; nothing is held back after that")
    }

    // MARK: - What the bulk key is allowed to claim

    func testTheBulkKeySaysTheNumberWhenRowsAreHidden() {
        let title = RungWindow.selectAllTitle(selectableCount: 147, isTruncated: true, allTicked: false)

        XCTAssertEqual(
            title,
            "Select all 147",
            "it ticks copies the reader cannot see, so the count is the only honest way to say it"
        )
    }

    func testTheBulkKeyStaysPlainWhenEverythingIsOnScreen() {
        let title = RungWindow.selectAllTitle(selectableCount: 4, isTruncated: false, allTicked: false)

        XCTAssertEqual(title, "Select all", "nothing is hidden, so a number would be noise")
    }

    func testUntickingWinsOverTheCount() {
        let title = RungWindow.selectAllTitle(selectableCount: 147, isTruncated: true, allTicked: true)

        XCTAssertEqual(title, "Deselect all", "this one takes nothing, so it has nothing to declare")
    }
}
