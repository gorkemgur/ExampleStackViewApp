import XCTest
@testable import DupeCore

final class KeeperScorerTests: XCTestCase {

    func testFavouriteOutranksEveryQualitySignal() {
        let favourite = Fixtures.item("fav", bytes: 100, width: 640, height: 480, favorite: true)
        let better = Fixtures.item("big", bytes: 50_000_000, width: 8000, height: 6000, location: true)
        XCTAssertEqual(KeeperScorer.keeper(among: [better, favourite])?.id, "fav")
    }

    func testAlbumMembershipIsAlsoProtection() {
        let filed = Fixtures.item("filed", bytes: 100, width: 640, height: 480, albums: 2)
        let better = Fixtures.item("big", bytes: 50_000_000, width: 8000, height: 6000)
        XCTAssertEqual(KeeperScorer.keeper(among: [better, filed])?.id, "filed")
    }

    func testHighestResolutionWinsAmongEqualItems() {
        let small = Fixtures.item("small", bytes: 1000, width: 1000, height: 1000)
        let large = Fixtures.item("large", bytes: 1000, width: 4000, height: 3000)
        XCTAssertEqual(KeeperScorer.keeper(among: [small, large])?.id, "large")
    }

    func testEditedCopyBeatsAnUneditedOneOfTheSameSize() {
        let plain = Fixtures.item("plain")
        let edited = Fixtures.item("edited", edited: true)
        XCTAssertEqual(KeeperScorer.keeper(among: [plain, edited])?.id, "edited")
    }

    func testScreenshotIsPenalised() {
        let shot = Fixtures.item("shot", screenshot: true)
        let photo = Fixtures.item("photo")
        XCTAssertEqual(KeeperScorer.keeper(among: [shot, photo])?.id, "photo")
    }

    func testCloudOnlyCopyLosesToALocalOne() {
        let cloud = Fixtures.item("cloud", local: false)
        let local = Fixtures.item("local")
        XCTAssertEqual(KeeperScorer.keeper(among: [cloud, local])?.id, "local")
    }

    func testLivePhotoCountsItsPairedMovie() {
        let live = Fixtures.item("live", bytes: 1_000_000, pairedVideoBytes: 3_000_000, live: true)
        XCTAssertEqual(live.totalByteSize, 4_000_000)
        let still = Fixtures.item("still", bytes: 1_000_000)
        XCTAssertEqual(KeeperScorer.keeper(among: [still, live])?.id, "live")
    }

    func testResultIsIndependentOfInputOrder() {
        let items = [
            Fixtures.item("c", bytes: 10),
            Fixtures.item("a", bytes: 10),
            Fixtures.item("b", bytes: 10)
        ]
        let forward = KeeperScorer.keeper(among: items)?.id
        let backward = KeeperScorer.keeper(among: items.reversed())?.id
        XCTAssertEqual(forward, backward)
        XCTAssertEqual(forward, "a", "fully tied items resolve to the smallest id")
    }

    func testEarlierCaptureWinsWhenEverythingElseTies() {
        let old = Fixtures.item("old", created: Date(timeIntervalSince1970: 1_000))
        let new = Fixtures.item("new", created: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(KeeperScorer.keeper(among: [new, old])?.id, "old")
    }

    func testEmptyInput() {
        XCTAssertNil(KeeperScorer.keeper(among: []))
        XCTAssertTrue(KeeperScorer.scores(for: []).isEmpty)
    }
}

final class CleanupPlannerTests: XCTestCase {

    private func exactGroup(_ ids: [String]) -> DuplicateGroup {
        DuplicateGroup(id: "g", relation: .exact, seedID: ids[0], itemIDs: ids)
    }

    func testExactDuplicatesArePreTicked() {
        let items = Fixtures.index([
            Fixtures.item("a", bytes: 5_000_000, width: 4000, height: 3000),
            Fixtures.item("b", bytes: 5_000_000, width: 4000, height: 3000),
            Fixtures.item("c", bytes: 5_000_000, width: 4000, height: 3000)
        ])
        let decision = CleanupPlanner.decide(group: exactGroup(["a", "b", "c"]), items: items)!
        XCTAssertEqual(decision.keeperID, "a")
        XCTAssertEqual(decision.autoSelectedForDeletion, ["b", "c"])
        XCTAssertTrue(decision.manualReviewRequired.isEmpty)
    }

    func testProtectedCopiesAreNeverPreTicked() {
        let items = Fixtures.index([
            Fixtures.item("keeper", bytes: 9_000_000, width: 4000, height: 3000),
            Fixtures.item("favourite", bytes: 5_000_000, favorite: true),
            Fixtures.item("plain", bytes: 5_000_000)
        ])
        let decision = CleanupPlanner.decide(group: exactGroup(["keeper", "favourite", "plain"]), items: items)!
        XCTAssertEqual(decision.keeperID, "favourite", "protection outranks size")
        XCTAssertFalse(decision.autoSelectedForDeletion.contains("favourite"))
        XCTAssertEqual(decision.autoSelectedForDeletion, ["keeper", "plain"])
    }

    func testKeeperIsNeverACandidate() {
        let items = Fixtures.index([Fixtures.item("a"), Fixtures.item("b"), Fixtures.item("c")])
        let decision = CleanupPlanner.decide(group: exactGroup(["a", "b", "c"]), items: items)!
        XCTAssertFalse(decision.allCandidates.contains(decision.keeperID))
    }

    func testSimilarGroupsPreTickNothing() {
        let group = DuplicateGroup(id: "s", relation: .similar, seedID: "a", itemIDs: ["a", "b", "c"])
        let items = Fixtures.index([Fixtures.item("a"), Fixtures.item("b"), Fixtures.item("c")])
        let decision = CleanupPlanner.decide(group: group, items: items)!
        XCTAssertTrue(decision.autoSelectedForDeletion.isEmpty)
        XCTAssertEqual(decision.manualReviewRequired, ["b", "c"])
    }

    func testSimilarGroupKeepsTheSeedEvenIfAnotherCopyScoresHigher() {
        // The seed is the only item everything else was compared against, so it has to be the
        // survivor no matter how good the alternatives look.
        let group = DuplicateGroup(id: "s", relation: .similar, seedID: "seed", itemIDs: ["seed", "flashy"])
        let items = Fixtures.index([
            Fixtures.item("seed", bytes: 100, width: 640, height: 480),
            Fixtures.item("flashy", bytes: 90_000_000, width: 8000, height: 6000, favorite: true)
        ])
        let decision = CleanupPlanner.decide(group: group, items: items)!
        XCTAssertEqual(decision.keeperID, "seed")
        XCTAssertEqual(decision.manualReviewRequired, ["flashy"])
        XCTAssertTrue(decision.autoSelectedForDeletion.isEmpty)
    }

    func testNearExactPreTicksOnlyAStrictlyInferiorReEncode() {
        let group = DuplicateGroup(id: "n", relation: .nearExact, seedID: "original", itemIDs: ["original", "resend"])
        let items = Fixtures.index([
            Fixtures.item("original", bytes: 6_000_000, width: 4032, height: 3024),
            Fixtures.item("resend", bytes: 400_000, width: 1280, height: 960)
        ])
        let decision = CleanupPlanner.decide(group: group, items: items)!
        XCTAssertEqual(decision.autoSelectedForDeletion, ["resend"])
    }

    func testNearExactDoesNotPreTickAnEditedCopy() {
        let group = DuplicateGroup(id: "n", relation: .nearExact, seedID: "original", itemIDs: ["original", "edited"])
        let items = Fixtures.index([
            Fixtures.item("original", bytes: 6_000_000, width: 4032, height: 3024),
            Fixtures.item("edited", bytes: 400_000, width: 1280, height: 960, edited: true)
        ])
        let decision = CleanupPlanner.decide(group: group, items: items)!
        XCTAssertTrue(decision.autoSelectedForDeletion.isEmpty)
        XCTAssertEqual(decision.manualReviewRequired, ["edited"])
    }

    func testNearExactDoesNotPreTickWhenTheSurvivorIsCloudOnly() {
        let group = DuplicateGroup(id: "n", relation: .nearExact, seedID: "original", itemIDs: ["original", "resend"])
        let items = Fixtures.index([
            Fixtures.item("original", bytes: 6_000_000, width: 4032, height: 3024, local: false),
            Fixtures.item("resend", bytes: 400_000, width: 1280, height: 960)
        ])
        let decision = CleanupPlanner.decide(group: group, items: items)!
        XCTAssertTrue(decision.autoSelectedForDeletion.isEmpty)
    }

    func testNearExactDoesNotPreTickAnEqualResolutionCopy() {
        let group = DuplicateGroup(id: "n", relation: .nearExact, seedID: "a", itemIDs: ["a", "b"])
        let items = Fixtures.index([
            Fixtures.item("a", bytes: 6_000_000, width: 4032, height: 3024),
            Fixtures.item("b", bytes: 5_000_000, width: 4032, height: 3024)
        ])
        let decision = CleanupPlanner.decide(group: group, items: items)!
        XCTAssertTrue(decision.autoSelectedForDeletion.isEmpty, "same pixels could mean a different crop")
    }

    func testGroupWithMissingItemsIsDropped() {
        let group = exactGroup(["a", "ghost"])
        XCTAssertNil(CleanupPlanner.decide(group: group, items: Fixtures.index([Fixtures.item("a")])))
    }

    /// Whatever the planner proposes on its own must pass the validator untouched.
    func testAutoSelectionIsAlwaysValid() {
        var rng = SplitMix64(seed: 2024)
        var groups: [DuplicateGroup] = []
        var items: [MediaItem] = []

        for groupIndex in 0..<40 {
            let size = Int.random(in: 2...5, using: &rng)
            var ids: [String] = []
            for memberIndex in 0..<size {
                let id = "g\(groupIndex)-m\(memberIndex)"
                ids.append(id)
                items.append(
                    Fixtures.item(
                        id,
                        bytes: Int64.random(in: 1_000...50_000_000, using: &rng),
                        width: Int.random(in: 480...8000, using: &rng),
                        height: Int.random(in: 480...6000, using: &rng),
                        favorite: Bool.random(using: &rng),
                        albums: Int.random(in: 0...2, using: &rng),
                        edited: Bool.random(using: &rng),
                        local: Bool.random(using: &rng)
                    )
                )
            }
            let relation = DuplicateRelation.allCases[Int.random(in: 0..<DuplicateRelation.allCases.count, using: &rng)]
            groups.append(DuplicateGroup(id: "grp\(groupIndex)", relation: relation, seedID: ids[0], itemIDs: ids))
        }

        let index = Fixtures.index(items)
        let decisions = CleanupPlanner.decide(groups: groups, items: index)
        let selection = Set(decisions.flatMap(\.autoSelectedForDeletion))

        let violations = CleanupValidator.validate(
            selection: selection,
            decisions: decisions,
            knownItemIDs: Set(index.keys)
        )
        XCTAssertEqual(violations, [], "planner produced a selection its own validator rejects")
    }
}

final class CleanupValidatorTests: XCTestCase {

    private let decision = GroupDecision(
        id: "g1",
        relation: .exact,
        keeperID: "keep",
        autoSelectedForDeletion: ["dupe1"],
        manualReviewRequired: ["dupe2"]
    )

    private var known: Set<String> { ["keep", "dupe1", "dupe2", "loose"] }

    func testEmptySelectionIsSafe() {
        XCTAssertTrue(CleanupValidator.isSafe(selection: [], decisions: [decision], knownItemIDs: known))
    }

    func testNormalSelectionIsSafe() {
        XCTAssertTrue(
            CleanupValidator.isSafe(selection: ["dupe1", "dupe2"], decisions: [decision], knownItemIDs: known)
        )
    }

    func testDeletingTheKeeperIsRejected() {
        let violations = CleanupValidator.validate(
            selection: ["keep"], decisions: [decision], knownItemIDs: known
        )
        XCTAssertTrue(violations.contains(.keeperSelectedForDeletion(groupID: "g1", itemID: "keep")))
    }

    func testWipingAWholeGroupIsRejected() {
        let violations = CleanupValidator.validate(
            selection: ["keep", "dupe1", "dupe2"], decisions: [decision], knownItemIDs: known
        )
        XCTAssertTrue(violations.contains(.groupFullyDeleted(groupID: "g1")))
    }

    func testItemOutsideAnyGroupIsRejected() {
        let violations = CleanupValidator.validate(
            selection: ["loose"], decisions: [decision], knownItemIDs: known
        )
        XCTAssertEqual(violations, [.itemNotInAnyGroup(itemID: "loose")])
    }

    func testUnknownItemIsRejected() {
        let violations = CleanupValidator.validate(
            selection: ["vanished"], decisions: [decision], knownItemIDs: known
        )
        XCTAssertEqual(violations, [.unknownItem(itemID: "vanished")])
    }

    func testItemSharedBetweenGroupsIsRejected() {
        let other = GroupDecision(
            id: "g2",
            relation: .exact,
            keeperID: "other",
            autoSelectedForDeletion: ["dupe1"],
            manualReviewRequired: []
        )
        let violations = CleanupValidator.validate(
            selection: [], decisions: [decision, other], knownItemIDs: known.union(["other"])
        )
        XCTAssertTrue(violations.contains(.itemInMultipleGroups(itemID: "dupe1")))
    }
}

final class SavingsCalculatorTests: XCTestCase {

    func testSplitsByWhenTheSpaceActuallyComesBack() {
        let items = Fixtures.index([
            Fixtures.item("photo", source: .photoLibrary, bytes: 3_000_000),
            Fixtures.item("file", source: .fileFolder, kind: .document, bytes: 1_000_000),
            Fixtures.item("cloud", source: .photoLibrary, bytes: 9_000_000, local: false)
        ])
        let savings = SavingsCalculator.breakdown(for: ["photo", "file", "cloud"], items: items)

        XCTAssertEqual(savings.deferredBytes, 3_000_000, "photo library deletions wait on Recently Deleted")
        XCTAssertEqual(savings.immediateBytes, 1_000_000)
        XCTAssertEqual(savings.cloudOnlyBytes, 9_000_000, "not on this device, so not device space")
        XCTAssertEqual(savings.onDeviceBytes, 4_000_000)
        XCTAssertEqual(savings.totalBytes, 13_000_000)
        XCTAssertEqual(savings.itemCount, 3)
    }

    func testLivePhotoMovieIsCounted() {
        let items = Fixtures.index([
            Fixtures.item("live", bytes: 2_000_000, pairedVideoBytes: 5_000_000, live: true)
        ])
        XCTAssertEqual(SavingsCalculator.breakdown(for: ["live"], items: items).deferredBytes, 7_000_000)
    }

    func testUnknownIDsAreIgnoredRatherThanCounted() {
        let items = Fixtures.index([Fixtures.item("a", bytes: 10)])
        let savings = SavingsCalculator.breakdown(for: ["a", "ghost"], items: items)
        XCTAssertEqual(savings.itemCount, 1)
        XCTAssertEqual(savings.totalBytes, 10)
    }

    func testBreakdownByKind() {
        let items = Fixtures.index([
            Fixtures.item("i", kind: .image, bytes: 100),
            Fixtures.item("v", kind: .video, bytes: 900),
            Fixtures.item("v2", kind: .video, bytes: 100)
        ])
        let savings = SavingsCalculator.breakdown(for: ["i", "v", "v2"], items: items)
        XCTAssertEqual(savings.bytesByKind[.image], 100)
        XCTAssertEqual(savings.bytesByKind[.video], 1000)
        XCTAssertNil(savings.bytesByKind[.document])
    }

    func testEmptySelection() {
        XCTAssertEqual(SavingsCalculator.breakdown(for: [], items: [:]), .empty)
    }
}
