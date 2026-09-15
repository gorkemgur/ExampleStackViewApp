import Foundation

/// How much of one rung the review list draws, and what it says about the rest.
///
/// A rung used to draw every group it held. On the fixture that is four rows; on a real library
/// the bottom rung — the one nothing is ever ticked in, because `.similar` is not lossless and
/// `RegretTier` will not pre-select it — can hold hundreds, and a screen that opens onto
/// hundreds of unticked rows reads as a pile of work rather than as an offer.
///
/// The rule is the same for every rung. A cap that applied only to `.similar` would be a
/// special case waiting to be wrong the first time somebody's library holds four hundred
/// byte-identical copies.
enum RungWindow {

    /// Rows drawn before the rest are folded away.
    static let limit = 5

    struct State: Equatable {
        let shown: Int
        let hidden: Int

        var isTruncated: Bool { hidden > 0 }
    }

    static func state(groupCount: Int, isExpanded: Bool) -> State {
        // One row over the limit is left alone. Folding a single group away to make room for a
        // line announcing that a single group was folded away costs the same vertical space and
        // buys a tap.
        guard !isExpanded, groupCount > limit + 1 else {
            return State(shown: groupCount, hidden: 0)
        }
        return State(shown: limit, hidden: groupCount - limit)
    }

    /// What the rung's bulk key says.
    ///
    /// It reaches every candidate in the rung, including the ones folded away, and this screen
    /// has one rule it will not break: nothing is ticked that the reader cannot see happening.
    /// A key that silently took a hundred and fifty hidden photographs would be the worst thing
    /// this app could do, so when rows are hidden the key stops saying "all" and says the
    /// number instead.
    static func selectAllTitle(selectableCount: Int, isTruncated: Bool, allTicked: Bool) -> String {
        if allTicked { return "Deselect all" }
        return isTruncated ? "Select all \(selectableCount)" : "Select all"
    }
}
