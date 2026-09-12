import XCTest
@testable import DupeCore

final class TierClassifierTests: XCTestCase {

    private func decision(
        _ relation: DuplicateRelation,
        keeper: String,
        auto: [String] = [],
        manual: [String] = []
    ) -> GroupDecision {
        GroupDecision(
            id: "g",
            relation: relation,
            keeperID: keeper,
            autoSelectedForDeletion: auto,
            manualReviewRequired: manual
        )
    }

    private func group(_ relation: DuplicateRelation, seed: String, ids: [String]) -> DuplicateGroup {
        DuplicateGroup(id: "g", relation: relation, seedID: seed, itemIDs: ids)
    }

    func testExactCopiesAreTierZero() {
        let items = Fixtures.index([Fixtures.item("keep"), Fixtures.item("dupe")])
        let candidates = TierClassifier.candidates(
            for: decision(.exact, keeper: "keep", auto: ["dupe"]),
            group: group(.exact, seed: "keep", ids: ["keep", "dupe"]),
            items: items
        )
        XCTAssertEqual(candidates.map(\.tier), [.identical])
        XCTAssertTrue(candidates[0].isPreSelected)
        XCTAssertEqual(candidates[0].keeperID, "keep")
    }

    // MARK: - The two refusals a tier cannot express

    /// A favourite, or a copy in an album, is byte-for-byte identical to the survivor and
    /// therefore `.identical` — which is true and beside the point. `CleanupPlanner` refuses to
    /// pre-tick it; nothing downstream could see that refusal, so the budget key ticked it.
    func testAFavouriteIsIdenticalAndStillNeedsAHuman() {
        let items = Fixtures.index([Fixtures.item("keep"), Fixtures.item("loved", favorite: true)])
        let candidates = TierClassifier.candidates(
            for: decision(.exact, keeper: "keep", manual: ["loved"]),
            group: group(.exact, seed: "keep", ids: ["keep", "loved"]),
            items: items
        )

        XCTAssertEqual(candidates.map(\.tier), [.identical])
        XCTAssertTrue(candidates[0].requiresHuman)
    }

    func testACopyInAnAlbumNeedsAHuman() {
        let items = Fixtures.index([Fixtures.item("keep"), Fixtures.item("filed", albums: 2)])
        let candidates = TierClassifier.candidates(
            for: decision(.exact, keeper: "keep", manual: ["filed"]),
            group: group(.exact, seed: "keep", ids: ["keep", "filed"]),
            items: items
        )

        XCTAssertTrue(candidates[0].requiresHuman)
    }

    /// The worse one. The survivor is in iCloud and this is the only copy still on the phone,
    /// so a bulk control taking it leaves the user with a photograph they cannot open offline.
    func testACopyWhoseSurvivorIsOnlyInICloudNeedsAHuman() {
        let items = Fixtures.index([
            Fixtures.item("keep", local: false),
            Fixtures.item("here")
        ])
        let candidates = TierClassifier.candidates(
            for: decision(.exact, keeper: "keep", manual: ["here"]),
            group: group(.exact, seed: "keep", ids: ["keep", "here"]),
            items: items
        )

        XCTAssertEqual(candidates.map(\.tier), [.identical])
        XCTAssertTrue(candidates[0].requiresHuman)
    }

    func testAnOrdinaryCopyDoesNotNeedAHuman() {
        let items = Fixtures.index([Fixtures.item("keep"), Fixtures.item("dupe")])
        let candidates = TierClassifier.candidates(
            for: decision(.exact, keeper: "keep", auto: ["dupe"]),
            group: group(.exact, seed: "keep", ids: ["keep", "dupe"]),
            items: items
        )

        XCTAssertFalse(candidates[0].requiresHuman)
    }

    func testAnEditedCopyIsNotFiledUnderNoLossEvenWhenBytesMatch() {
        let items = Fixtures.index([
            Fixtures.item("keep"),
            Fixtures.item("edited", edited: true)
        ])
        let candidates = TierClassifier.candidates(
            for: decision(.exact, keeper: "keep", manual: ["edited"]),
            group: group(.exact, seed: "keep", ids: ["keep", "edited"]),
            items: items
        )
        XCTAssertEqual(candidates.map(\.tier), [.similar])
        XCTAssertFalse(candidates[0].isPreSelected)
    }

    func testAnEditedSurvivorDoesNotDemoteAPlainCopy() {
        let items = Fixtures.index([
            Fixtures.item("keep", edited: true),
            Fixtures.item("plain")
        ])
        let candidates = TierClassifier.candidates(
            for: decision(.exact, keeper: "keep", auto: ["plain"]),
            group: group(.exact, seed: "keep", ids: ["keep", "plain"]),
            items: items
        )
        XCTAssertEqual(candidates.map(\.tier), [.identical], "the plain copy has nothing to lose")
        XCTAssertTrue(candidates[0].isPreSelected)
    }

    func testStrictlyWorseReEncodeIsTierOne() {
        let items = Fixtures.index([
            Fixtures.item("original", bytes: 6_000_000, width: 4032, height: 3024),
            Fixtures.item("resend", bytes: 400_000, width: 1280, height: 960)
        ])
        let candidates = TierClassifier.candidates(
            for: decision(.nearExact, keeper: "original", auto: ["resend"]),
            group: group(.nearExact, seed: "original", ids: ["original", "resend"]),
            items: items
        )
        XCTAssertEqual(candidates.map(\.tier), [.inferiorCopy])
        XCTAssertTrue(candidates[0].isPreSelected)
    }

    func testEqualResolutionReEncodeFallsToTheManualTier() {
        let items = Fixtures.index([
            Fixtures.item("a", bytes: 6_000_000, width: 4032, height: 3024),
            Fixtures.item("b", bytes: 5_000_000, width: 4032, height: 3024)
        ])
        let candidates = TierClassifier.candidates(
            for: decision(.nearExact, keeper: "a", manual: ["b"]),
            group: group(.nearExact, seed: "a", ids: ["a", "b"]),
            items: items
        )
        XCTAssertEqual(candidates.map(\.tier), [.similar])
        XCTAssertFalse(candidates[0].isPreSelected)
    }

    func testBurstFramesGetTheirOwnTier() {
        var keeper = Fixtures.item("sharp")
        keeper.burstIdentifier = "burst-1"
        var frame = Fixtures.item("blurry")
        frame.burstIdentifier = "burst-1"

        let candidates = TierClassifier.candidates(
            for: decision(.similar, keeper: "sharp", manual: ["blurry"]),
            group: group(.similar, seed: "sharp", ids: ["sharp", "blurry"]),
            items: Fixtures.index([keeper, frame])
        )
        XCTAssertEqual(candidates.map(\.tier), [.burstLeftover])
        XCTAssertFalse(candidates[0].isPreSelected, "a burst frame still needs a human")
    }

    func testDifferentBurstsAreNotBurstLeftovers() {
        var keeper = Fixtures.item("a")
        keeper.burstIdentifier = "burst-1"
        var other = Fixtures.item("b")
        other.burstIdentifier = "burst-2"

        let candidates = TierClassifier.candidates(
            for: decision(.similar, keeper: "a", manual: ["b"]),
            group: group(.similar, seed: "a", ids: ["a", "b"]),
            items: Fixtures.index([keeper, other])
        )
        XCTAssertEqual(candidates.map(\.tier), [.similar])
    }

    /// Pre-selection is a promise that deleting costs nothing. A tier above `inferiorCopy`
    /// cannot make that promise, whatever an upstream decision claimed.
    func testPreSelectionIsNeverWidenedBeyondTheLosslessTiers() {
        var keeper = Fixtures.item("keep")
        keeper.burstIdentifier = "b"
        var frame = Fixtures.item("frame")
        frame.burstIdentifier = "b"

        let candidates = TierClassifier.candidates(
            for: decision(.similar, keeper: "keep", auto: ["frame"]),
            group: group(.similar, seed: "keep", ids: ["keep", "frame"]),
            items: Fixtures.index([keeper, frame])
        )
        XCTAssertFalse(candidates[0].isPreSelected)
    }

    func testKeeperIsNeverACandidate() {
        let items = Fixtures.index([Fixtures.item("keep"), Fixtures.item("a"), Fixtures.item("b")])
        let candidates = TierClassifier.candidates(
            for: decision(.exact, keeper: "keep", auto: ["a", "b"]),
            group: group(.exact, seed: "keep", ids: ["keep", "a", "b"]),
            items: items
        )
        XCTAssertFalse(candidates.map(\.id).contains("keep"))
    }

    func testMissingItemsAreSkipped() {
        let candidates = TierClassifier.candidates(
            for: decision(.exact, keeper: "keep", auto: ["ghost"]),
            group: group(.exact, seed: "keep", ids: ["keep", "ghost"]),
            items: Fixtures.index([Fixtures.item("keep")])
        )
        XCTAssertTrue(candidates.isEmpty)
    }
}

final class BudgetPlannerTests: XCTestCase {

    private func candidate(
        _ id: String,
        tier: RegretTier,
        bytes: Int64,
        preSelected: Bool = false,
        requiresHuman: Bool = false
    ) -> DeletionCandidate {
        DeletionCandidate(
            id: id,
            groupID: "g-\(id)",
            keeperID: "keeper-\(id)",
            tier: tier,
            bytes: bytes,
            isPreSelected: preSelected,
            requiresHuman: requiresHuman
        )
    }

    // MARK: - What a bulk control may not touch

    /// The plan is a bulk control: it ticks copies in groups nobody has opened. A tier says
    /// what information is lost, and that is not the same question as whether this is a copy
    /// the person has told us matters.
    func testAPlanNeverTicksACopyThatNeedsAHuman() {
        let plan = BudgetPlanner.plan(
            target: 10_000,
            candidates: [
                candidate("favourite", tier: .identical, bytes: 5_000, requiresHuman: true),
                candidate("plain", tier: .identical, bytes: 1_000)
            ],
            allowedTiers: [.identical]
        )

        XCTAssertEqual(plan.selectedIDs, ["plain"])
        XCTAssertEqual(plan.reclaimedBytes, 1_000)
        XCTAssertFalse(plan.meetsTarget, "and it says it fell short rather than reaching for the one it may not take")
    }

    /// The veto holds at every depth, including the ones the user opted into. "+ similar" is
    /// consent to judgement calls in general, not consent to delete a favourite.
    func testTheVetoHoldsAtEveryDepth() {
        for depth in RegretTier.allCases {
            let plan = BudgetPlanner.plan(
                target: 999_999,
                candidates: [candidate("favourite", tier: depth, bytes: 5_000, requiresHuman: true)],
                allowedTiers: Set(RegretTier.allCases)
            )
            XCTAssertTrue(plan.selected.isEmpty, "a vetoed copy was taken at \(depth)")
        }
    }

    /// And the veto is not `isPreSelected` wearing another name: nothing in a burst or a
    /// similar group is ever pre-selected, so a plan that required it would select nothing at
    /// the two depths the user explicitly asked for.
    func testADepthTheUserAskedForStillSelectsThingsNobodyPreSelected() {
        let plan = BudgetPlanner.plan(
            target: 999_999,
            candidates: [candidate("burst", tier: .burstLeftover, bytes: 5_000, preSelected: false)],
            allowedTiers: [.identical, .inferiorCopy, .burstLeftover]
        )

        XCTAssertEqual(plan.selectedIDs, ["burst"])
    }

    func testSummariesAccumulateAcrossTiers() {
        let summaries = BudgetPlanner.summaries(for: [
            candidate("a", tier: .identical, bytes: 100),
            candidate("b", tier: .identical, bytes: 200),
            candidate("c", tier: .similar, bytes: 700)
        ])
        XCTAssertEqual(summaries.map(\.tier), [.identical, .similar])
        XCTAssertEqual(summaries[0].bytes, 300)
        XCTAssertEqual(summaries[0].itemCount, 2)
        XCTAssertEqual(summaries[0].cumulativeBytes, 300)
        XCTAssertEqual(summaries[1].cumulativeBytes, 1000)
    }

    func testEmptyTiersAreOmitted() {
        let summaries = BudgetPlanner.summaries(for: [candidate("a", tier: .similar, bytes: 10)])
        XCTAssertEqual(summaries.map(\.tier), [.similar])
    }

    func testCheapestTiersAreSpentFirst() {
        let plan = BudgetPlanner.plan(target: 150, candidates: [
            candidate("expensive", tier: .similar, bytes: 1000),
            candidate("cheap", tier: .identical, bytes: 100),
            candidate("cheap2", tier: .identical, bytes: 100)
        ])
        XCTAssertEqual(plan.selected.map(\.id), ["cheap", "cheap2"])
        XCTAssertEqual(plan.reclaimedBytes, 200)
        XCTAssertEqual(plan.deepestTier, .identical)
        XCTAssertTrue(plan.meetsTarget)
    }

    func testLargestItemsFirstWithinATier() {
        let plan = BudgetPlanner.plan(target: 1, candidates: [
            candidate("small", tier: .identical, bytes: 10),
            candidate("big", tier: .identical, bytes: 900)
        ])
        XCTAssertEqual(plan.selected.map(\.id), ["big"], "fewest deletions to reach the target")
    }

    func testStopsAsSoonAsTheTargetIsMet() {
        let plan = BudgetPlanner.plan(target: 100, candidates: (0..<10).map {
            candidate("i\($0)", tier: .identical, bytes: 60)
        })
        XCTAssertEqual(plan.selected.count, 2)
        XCTAssertEqual(plan.reclaimedBytes, 120)
    }

    func testUnreachableTargetReportsTheShortfall() {
        let plan = BudgetPlanner.plan(target: 10_000, candidates: [
            candidate("a", tier: .identical, bytes: 400)
        ])
        XCTAssertFalse(plan.meetsTarget)
        XCTAssertEqual(plan.reclaimedBytes, 400)
        XCTAssertEqual(plan.shortfallBytes, 9_600)
    }

    func testDisallowedTiersAreNeverSpent() {
        let plan = BudgetPlanner.plan(
            target: 10_000,
            candidates: [
                candidate("safe", tier: .identical, bytes: 100),
                candidate("risky", tier: .similar, bytes: 9_000)
            ],
            allowedTiers: RegretTier.losslessTiers
        )
        XCTAssertEqual(plan.selected.map(\.id), ["safe"])
        XCTAssertFalse(plan.meetsTarget)
    }

    func testZeroAndNegativeTargetsPlanNothing() {
        let candidates = [candidate("a", tier: .identical, bytes: 100)]
        XCTAssertEqual(BudgetPlanner.plan(target: 0, candidates: candidates), .empty)
        XCTAssertTrue(BudgetPlanner.plan(target: -5, candidates: candidates).selected.isEmpty)
    }

    func testZeroByteCandidatesAreIgnored() {
        let plan = BudgetPlanner.plan(target: 10, candidates: [candidate("empty", tier: .identical, bytes: 0)])
        XCTAssertTrue(plan.selected.isEmpty)
    }

    func testLosslessPlanTakesOnlyPreSelectedItems() {
        let plan = BudgetPlanner.losslessPlan(candidates: [
            candidate("a", tier: .identical, bytes: 100, preSelected: true),
            candidate("b", tier: .inferiorCopy, bytes: 50, preSelected: true),
            candidate("c", tier: .similar, bytes: 900, preSelected: false)
        ])
        XCTAssertEqual(plan.selected.map(\.id), ["a", "b"])
        XCTAssertEqual(plan.reclaimedBytes, 150)
        XCTAssertEqual(plan.deepestTier, .inferiorCopy)
        XCTAssertTrue(plan.meetsTarget)
    }

    func testPlanIsDeterministicForTiedCandidates() {
        let candidates = [
            candidate("z", tier: .identical, bytes: 100),
            candidate("a", tier: .identical, bytes: 100)
        ]
        let first = BudgetPlanner.plan(target: 100, candidates: candidates)
        let second = BudgetPlanner.plan(target: 100, candidates: candidates.reversed())
        XCTAssertEqual(first.selected.map(\.id), second.selected.map(\.id))
        XCTAssertEqual(first.selected.map(\.id), ["a"])
    }

    /// Whatever the budget slider lands on, the resulting selection has to survive the same
    /// gate a hand-made selection does.
    func testAnyBudgetPlanPassesTheCleanupValidator() {
        var rng = SplitMix64(seed: 8080)
        var groups: [DuplicateGroup] = []
        var items: [MediaItem] = []

        for groupIndex in 0..<30 {
            let size = Int.random(in: 2...4, using: &rng)
            var ids: [String] = []
            for memberIndex in 0..<size {
                let id = "g\(groupIndex)-m\(memberIndex)"
                ids.append(id)
                items.append(
                    Fixtures.item(
                        id,
                        bytes: Int64.random(in: 1_000...9_000_000, using: &rng),
                        width: Int.random(in: 480...6000, using: &rng),
                        height: Int.random(in: 480...4000, using: &rng),
                        favorite: Bool.random(using: &rng),
                        edited: Bool.random(using: &rng)
                    )
                )
            }
            let relation = DuplicateRelation.allCases[Int.random(in: 0..<3, using: &rng)]
            groups.append(DuplicateGroup(id: "grp\(groupIndex)", relation: relation, seedID: ids[0], itemIDs: ids))
        }

        let index = Fixtures.index(items)
        let decisions = CleanupPlanner.decide(groups: groups, items: index)
        let candidates = TierClassifier.candidates(decisions: decisions, groups: groups, items: index)

        for target in [Int64(1), 1_000_000, 50_000_000, 10_000_000_000] {
            let plan = BudgetPlanner.plan(target: target, candidates: candidates)
            let violations = CleanupValidator.validate(
                selection: plan.selectedIDs,
                decisions: decisions,
                knownItemIDs: Set(index.keys)
            )
            XCTAssertEqual(violations, [], "budget plan for \(target) bytes was rejected")
        }
    }
}
