import XCTest
@testable import DupeCore

final class GroupOverrideTests: XCTestCase {

    private func decision(
        relation: DuplicateRelation,
        keeper: String = "a",
        auto: [String] = ["b"],
        manual: [String] = ["c"]
    ) -> GroupDecision {
        GroupDecision(
            id: "g1",
            relation: relation,
            keeperID: keeper,
            autoSelectedForDeletion: auto,
            manualReviewRequired: manual
        )
    }

    func testNoOverrideChangesNothing() {
        let original = decision(relation: .exact)
        XCTAssertEqual(GroupRevision.apply(GroupOverride(), to: original), original)
    }

    func testChoosingTheSameKeeperChangesNothing() {
        let original = decision(relation: .exact)
        XCTAssertEqual(
            GroupRevision.apply(GroupOverride(keeperID: "a"), to: original),
            original
        )
    }

    func testSomethingOutsideTheGroupIsIgnored() {
        let original = decision(relation: .exact)
        XCTAssertEqual(
            GroupRevision.apply(GroupOverride(keeperID: "zzz"), to: original),
            original
        )
    }

    /// Digest equality is transitive, so in an exact group every member is interchangeable and
    /// the user may keep any of them without costing the rest of the group.
    func testInAnExactGroupAnyCopyMayStayAndTheRestStayOnOffer() {
        let revised = GroupRevision.apply(
            GroupOverride(keeperID: "c"),
            to: decision(relation: .exact)
        )

        XCTAssertEqual(revised.keeperID, "c")
        XCTAssertEqual(revised.allCandidates.sorted(), ["a", "b"])
        XCTAssertEqual(GroupRevision.droppedMembers(GroupOverride(keeperID: "c"), of: decision(relation: .exact)), [])
    }

    /// The first rule, enforced where it would otherwise be broken: in a star group every member
    /// was measured against the seed and against nothing else, so keeping some other copy leaves
    /// only the seed with direct evidence against it.
    func testKeepingSomethingElseInAStarGroupLeavesOnlyTheSeedOnOffer() {
        for relation in [DuplicateRelation.nearExact, .similar] {
            let original = decision(relation: relation)
            let override = GroupOverride(keeperID: "c")
            let revised = GroupRevision.apply(override, to: original)

            XCTAssertEqual(revised.keeperID, "c")
            XCTAssertEqual(
                revised.allCandidates, ["a"],
                "\(relation): only the copy everything was measured against may still be deleted"
            )
            XCTAssertEqual(
                GroupRevision.droppedMembers(override, of: original), ["b"],
                "\(relation): the member nobody compared with the new survivor has to be dropped"
            )
        }
    }

    /// A tick the app placed under its own assumption is not an answer to the question the user
    /// just asked by overruling it.
    func testNothingStaysPreTickedAfterAnOverride() {
        let revised = GroupRevision.apply(
            GroupOverride(keeperID: "b"),
            to: decision(relation: .exact)
        )
        XCTAssertTrue(revised.autoSelectedForDeletion.isEmpty)
    }

    func testAppliesAcrossDecisionsAndLeavesUntouchedOnesAlone() {
        let first = decision(relation: .exact)
        let second = GroupDecision(
            id: "g2",
            relation: .exact,
            keeperID: "x",
            autoSelectedForDeletion: ["y"],
            manualReviewRequired: []
        )

        let revised = GroupRevision.apply(["g1": GroupOverride(keeperID: "b")], to: [first, second])

        XCTAssertEqual(revised[0].keeperID, "b")
        XCTAssertEqual(revised[1], second)
    }
}

final class ClearedGroupValidationTests: XCTestCase {

    private let decisions = [
        GroupDecision(
            id: "g1",
            relation: .exact,
            keeperID: "a",
            autoSelectedForDeletion: ["b"],
            manualReviewRequired: []
        )
    ]
    private let known: Set<String> = ["a", "b"]

    /// Unchanged, and the reason the rest of this app can be trusted: nothing the engine works
    /// out on its own may empty a group or delete a survivor.
    func testEmptyingAGroupIsStillRefusedByDefault() {
        let violations = CleanupValidator.validate(
            selection: ["a", "b"],
            decisions: decisions,
            knownItemIDs: known
        )
        XCTAssertTrue(violations.contains(.groupFullyDeleted(groupID: "g1")))
        XCTAssertTrue(violations.contains(.keeperSelectedForDeletion(groupID: "g1", itemID: "a")))
    }

    func testAGroupTheUserAskedToClearIsAllowedToLoseEverything() {
        let violations = CleanupValidator.validate(
            selection: ["a", "b"],
            decisions: decisions,
            knownItemIDs: known,
            clearedGroupIDs: ["g1"]
        )
        XCTAssertEqual(violations, [], "the user asked for this one by name")
    }

    /// Clearing one group says nothing about any other.
    func testClearingOneGroupDoesNotExcuseAnother() {
        let second = GroupDecision(
            id: "g2",
            relation: .exact,
            keeperID: "x",
            autoSelectedForDeletion: ["y"],
            manualReviewRequired: []
        )

        let violations = CleanupValidator.validate(
            selection: ["a", "b", "x", "y"],
            decisions: decisions + [second],
            knownItemIDs: ["a", "b", "x", "y"],
            clearedGroupIDs: ["g1"]
        )

        XCTAssertTrue(violations.contains(.groupFullyDeleted(groupID: "g2")))
        XCTAssertFalse(violations.contains(.groupFullyDeleted(groupID: "g1")))
    }
}

final class ScanStrictnessTests: XCTestCase {

    func testStricterMeansACloserMatchIsRequired() {
        let strict = ScanStrictness.strict.configuration
        let balanced = ScanStrictness.balanced.configuration
        let loose = ScanStrictness.loose.configuration

        XCTAssertLessThan(strict.nearExactDistance, balanced.nearExactDistance)
        XCTAssertLessThan(balanced.nearExactDistance, loose.nearExactDistance)
        XCTAssertLessThan(strict.similarDistance, balanced.similarDistance)
        XCTAssertLessThan(balanced.similarDistance, loose.similarDistance)
    }

    /// The configuration clamps this itself, and the ordering has to survive it: a threshold for
    /// "worth showing at all" below the one for "the same shot" would be incoherent.
    func testTheSimilarThresholdIsNeverTighterThanTheNearExactOne() {
        for level in ScanStrictness.allCases {
            XCTAssertGreaterThanOrEqual(
                level.configuration.similarDistance,
                level.configuration.nearExactDistance,
                "\(level)"
            )
        }
    }

    func testBalancedIsTheDefaultTheAppShippedWith() {
        XCTAssertEqual(ScanStrictness.balanced.configuration, .default)
    }

    func testEveryLevelSaysWhatItCostsYou() {
        for level in ScanStrictness.allCases {
            XCTAssertFalse(level.title.isEmpty)
            XCTAssertFalse(level.explanation.isEmpty, "\(level) has no explanation on screen")
        }
    }

    /// Nothing here may loosen a safety rule. Video matching gets wider thresholds too, but a
    /// single bad frame still vetoes a match at every level.
    func testEveryLevelStillVetoesOnOneBadFrame() {
        for level in ScanStrictness.allCases {
            let configuration = level.configuration
            XCTAssertGreaterThan(
                Double(configuration.videoWorstFrameDistance),
                configuration.videoAverageDistance,
                "\(level): the veto has to be a higher bar than the average, or it never fires"
            )
        }
    }
}
