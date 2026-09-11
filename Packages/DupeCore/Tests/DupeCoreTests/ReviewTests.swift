import XCTest
@testable import DupeCore

final class CleanupSelectionTests: XCTestCase {

    private let candidates = [
        DeletionCandidate(id: "a", groupID: "g1", keeperID: "k1", tier: .identical, bytes: 10, isPreSelected: true),
        DeletionCandidate(id: "b", groupID: "g1", keeperID: "k1", tier: .identical, bytes: 20, isPreSelected: true),
        DeletionCandidate(id: "c", groupID: "g2", keeperID: "k2", tier: .similar, bytes: 30, isPreSelected: false)
    ]

    func testOpensWithOnlyWhatTheEngineVouchesFor() {
        let selection = CleanupSelection.preSelected(from: candidates)
        XCTAssertEqual(selection.selectedIDs, ["a", "b"])
        XCTAssertFalse(selection.isSelected("c"), "a judgement call must start untouched")
    }

    func testToggle() {
        var selection = CleanupSelection.preSelected(from: candidates)
        selection.toggle("c")
        XCTAssertTrue(selection.isSelected("c"))
        selection.toggle("c")
        XCTAssertFalse(selection.isSelected("c"))
    }

    func testBulkSetAndClear() {
        var selection = CleanupSelection()
        selection.setSelected(true, for: ["a", "b"])
        XCTAssertEqual(selection.count, 2)
        selection.setSelected(false, for: ["a"])
        XCTAssertEqual(selection.selectedIDs, ["b"])
        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }

    func testContainsAllIsFalseForAPartialSection() {
        var selection = CleanupSelection()
        selection.setSelected(true, for: ["a"])
        XCTAssertFalse(selection.containsAll(["a", "b"]), "a half-ticked section must not read as on")
        selection.setSelected(true, for: ["b"])
        XCTAssertTrue(selection.containsAll(["a", "b"]))
    }

    func testContainsAllIsFalseForNothing() {
        XCTAssertFalse(CleanupSelection().containsAll([]))
    }

    func testReplaceSwapsTheWholeSelection() {
        var selection = CleanupSelection.preSelected(from: candidates)
        selection.replace(with: ["c"])
        XCTAssertEqual(selection.selectedIDs, ["c"])
    }
}

final class ReviewBuilderTests: XCTestCase {

    private func result(items: [MediaItem], candidates: [DeletionCandidate], decisions: [GroupDecision] = []) -> ScanResult {
        ScanResult(
            items: Fixtures.index(items),
            groups: [],
            decisions: decisions,
            candidates: candidates,
            cloudOnlyIDs: []
        )
    }

    func testSectionsAreOrderedFromCheapestTierToMostExpensive() {
        let items = [
            Fixtures.item("k1"), Fixtures.item("a"),
            Fixtures.item("k2"), Fixtures.item("b")
        ]
        let candidates = [
            DeletionCandidate(id: "b", groupID: "g2", keeperID: "k2", tier: .similar, bytes: 900, isPreSelected: false),
            DeletionCandidate(id: "a", groupID: "g1", keeperID: "k1", tier: .identical, bytes: 100, isPreSelected: true)
        ]
        let sections = ReviewBuilder.sections(for: result(items: items, candidates: candidates))

        XCTAssertEqual(sections.map(\.tier), [.identical, .similar])
        XCTAssertEqual(sections[0].bytes, 100)
        XCTAssertEqual(sections[1].bytes, 900)
    }

    func testGroupsWithinASectionAreOrderedByWhatTheyAreWorth() {
        let items = [
            Fixtures.item("k1"), Fixtures.item("small"),
            Fixtures.item("k2"), Fixtures.item("big")
        ]
        let candidates = [
            DeletionCandidate(id: "small", groupID: "g1", keeperID: "k1", tier: .identical, bytes: 10, isPreSelected: true),
            DeletionCandidate(id: "big", groupID: "g2", keeperID: "k2", tier: .identical, bytes: 5_000, isPreSelected: true)
        ]
        let sections = ReviewBuilder.sections(for: result(items: items, candidates: candidates))
        XCTAssertEqual(sections[0].groups.map(\.keeper.id), ["k2", "k1"])
    }

    /// A group can hold one strictly worse re-encode and one merely similar shot. Filing the
    /// whole group under the cheaper tier would quietly promote the risky half.
    func testAGroupStraddlingTwoTiersAppearsInBothWithOnlyItsOwnCandidates() {
        let items = [Fixtures.item("keeper"), Fixtures.item("worse"), Fixtures.item("alike")]
        let candidates = [
            DeletionCandidate(id: "worse", groupID: "g", keeperID: "keeper", tier: .inferiorCopy, bytes: 100, isPreSelected: true),
            DeletionCandidate(id: "alike", groupID: "g", keeperID: "keeper", tier: .similar, bytes: 200, isPreSelected: false)
        ]
        let sections = ReviewBuilder.sections(for: result(items: items, candidates: candidates))

        XCTAssertEqual(sections.map(\.tier), [.inferiorCopy, .similar])
        XCTAssertEqual(sections[0].groups[0].candidateIDs, ["worse"])
        XCTAssertEqual(sections[1].groups[0].candidateIDs, ["alike"])
        XCTAssertEqual(sections[0].groups[0].keeper.id, "keeper")
        XCTAssertEqual(sections[1].groups[0].keeper.id, "keeper", "the survivor is the same photo in both")
        XCTAssertNotEqual(sections[0].groups[0].id, sections[1].groups[0].id, "ids must stay unique across sections")
    }

    func testKeeperIsNeverListedAsACandidate() {
        let items = [Fixtures.item("keeper"), Fixtures.item("dupe")]
        let candidates = [
            DeletionCandidate(id: "dupe", groupID: "g", keeperID: "keeper", tier: .identical, bytes: 1, isPreSelected: true)
        ]
        let sections = ReviewBuilder.sections(for: result(items: items, candidates: candidates))
        XCTAssertFalse(sections[0].groups[0].candidateIDs.contains("keeper"))
        XCTAssertEqual(sections[0].groups[0].items.map(\.id), ["dupe"])
    }

    func testGroupsWhoseKeeperVanishedAreDropped() {
        let candidates = [
            DeletionCandidate(id: "dupe", groupID: "g", keeperID: "ghost", tier: .identical, bytes: 1, isPreSelected: true)
        ]
        let sections = ReviewBuilder.sections(for: result(items: [Fixtures.item("dupe")], candidates: candidates))
        XCTAssertTrue(sections.isEmpty, "a group with no survivor must never be shown")
    }

    func testEmptyResultProducesNoSections() {
        XCTAssertTrue(ReviewBuilder.sections(for: .empty).isEmpty)
    }

    func testSectionTotalsAddUp() {
        let items = (0..<6).map { Fixtures.item("i\($0)") } + [Fixtures.item("k")]
        let candidates = (0..<6).map {
            DeletionCandidate(
                id: "i\($0)",
                groupID: "g\($0 % 2)",
                keeperID: "k",
                tier: .identical,
                bytes: Int64(($0 + 1) * 100),
                isPreSelected: true
            )
        }
        let sections = ReviewBuilder.sections(for: result(items: items, candidates: candidates))
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].itemCount, 6)
        XCTAssertEqual(sections[0].bytes, 2_100)
        XCTAssertEqual(Set(sections[0].candidateIDs).count, 6)
    }
}

final class ReviewPruningTests: XCTestCase {

    private func group(_ ids: [String], tier: RegretTier = .identical) -> ReviewGroup {
        ReviewGroup(
            id: "g",
            tier: tier,
            keeper: Fixtures.item("keeper"),
            candidates: ids.map {
                DeletionCandidate(id: $0, groupID: "g", keeperID: "keeper", tier: tier, bytes: 10, isPreSelected: true)
            },
            items: ids.map { Fixtures.item($0) }
        )
    }

    func testRemovingNothingLeavesTheGroupAlone() {
        let original = group(["a", "b"])
        XCTAssertEqual(original.removing([]), original)
    }

    func testRemovingSomeCopiesKeepsTheRest() {
        let pruned = group(["a", "b", "c"]).removing(["b"])
        XCTAssertEqual(pruned?.candidateIDs, ["a", "c"])
        XCTAssertEqual(pruned?.items.map(\.id), ["a", "c"], "the item list must track the candidate list")
    }

    func testAGroupWithNothingLeftToOfferDisappears() {
        XCTAssertNil(group(["a", "b"]).removing(["a", "b"]))
    }

    func testSectionDropsEmptiedGroupsAndThenItself() {
        let section = ReviewSection(tier: .identical, groups: [group(["a"]), group(["b"])])
        XCTAssertEqual(section.removing(["a"])?.groups.count, 1)
        XCTAssertNil(section.removing(["a", "b"]))
    }

    func testKeeperIsNeverPrunedAway() {
        let pruned = group(["a"]).removing(["keeper"])
        XCTAssertEqual(pruned?.keeper.id, "keeper")
        XCTAssertEqual(pruned?.candidateIDs, ["a"])
    }
}

final class ScanThrottleTests: XCTestCase {

    func testNominalRunsAtFullSpeed() {
        XCTAssertEqual(SystemThrottle.limit(base: 4, thermalState: .nominal, isLowPowerMode: false), 4)
    }

    func testWarmDeviceHalvesTheLoad() {
        XCTAssertEqual(SystemThrottle.limit(base: 4, thermalState: .fair, isLowPowerMode: false), 2)
    }

    func testHotDeviceDropsToOneReadAtATime() {
        XCTAssertEqual(SystemThrottle.limit(base: 8, thermalState: .serious, isLowPowerMode: false), 1)
        XCTAssertEqual(SystemThrottle.limit(base: 8, thermalState: .critical, isLowPowerMode: false), 1)
    }

    func testLowPowerModeOverridesEvenACoolDevice() {
        XCTAssertEqual(SystemThrottle.limit(base: 8, thermalState: .nominal, isLowPowerMode: true), 1)
    }

    func testLimitIsNeverZero() {
        XCTAssertEqual(SystemThrottle.limit(base: 1, thermalState: .fair, isLowPowerMode: false), 1)
        XCTAssertEqual(SystemThrottle.limit(base: 0, thermalState: .nominal, isLowPowerMode: false), 1)
        XCTAssertEqual(UnthrottledScan().concurrencyLimit(base: 0), 1)
    }
}
