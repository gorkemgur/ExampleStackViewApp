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

/// Date was computed on every item and asked by nothing. These hold the ordering that made it
/// askable — including the cases that decide whether the list is trustworthy to tick through.
final class ReviewOrderTests: XCTestCase {

    private func candidate(_ id: String, group: String, keeper: String, bytes: Int64) -> DeletionCandidate {
        DeletionCandidate(
            id: id,
            groupID: group,
            keeperID: keeper,
            tier: .identical,
            bytes: bytes,
            isPreSelected: true
        )
    }

    private func day(_ offset: Double) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset * 86_400)
    }

    /// keeper-old is the oldest and the smallest; keeper-new is the newest and the biggest.
    /// So the two orders have to disagree, or the test is not testing anything.
    private func fixture() -> (items: [String: MediaItem], candidates: [DeletionCandidate]) {
        let items = Fixtures.index([
            Fixtures.item("keeper-old", bytes: 1_000, created: day(0)),
            Fixtures.item("copy-old", bytes: 1_000, created: day(0)),
            Fixtures.item("keeper-mid", bytes: 5_000, created: day(100)),
            Fixtures.item("copy-mid", bytes: 5_000, created: day(100)),
            Fixtures.item("keeper-new", bytes: 9_000, created: day(200)),
            Fixtures.item("copy-new", bytes: 9_000, created: day(200))
        ])
        let candidates = [
            candidate("copy-old", group: "g-old", keeper: "keeper-old", bytes: 1_000),
            candidate("copy-mid", group: "g-mid", keeper: "keeper-mid", bytes: 5_000),
            candidate("copy-new", group: "g-new", keeper: "keeper-new", bytes: 9_000)
        ]
        return (items, candidates)
    }

    private func keepers(_ order: ReviewBuilder.Order) -> [String] {
        let (items, candidates) = fixture()
        let sections = ReviewBuilder.sections(candidates: candidates, items: items, order: order)
        return sections.first?.groups.map(\.keeper.id) ?? []
    }

    func testBiggestFirstIsStillTheDefault() {
        let (items, candidates) = fixture()
        let defaulted = ReviewBuilder.sections(candidates: candidates, items: items)

        XCTAssertEqual(defaulted.first?.groups.map(\.keeper.id), ["keeper-new", "keeper-mid", "keeper-old"])
        XCTAssertEqual(keepers(.biggest), defaulted.first?.groups.map(\.keeper.id))
    }

    func testOldestFirstUsesTheSurvivorsDate() {
        XCTAssertEqual(keepers(.oldest), ["keeper-old", "keeper-mid", "keeper-new"])
    }

    func testNewestFirstIsTheOppositeAndNotJustTheByteOrder() {
        XCTAssertEqual(keepers(.newest), ["keeper-new", "keeper-mid", "keeper-old"])
        XCTAssertEqual(keepers(.oldest), keepers(.newest).reversed())
    }

    /// A file in a granted folder can have no creation date at all. Putting those first in
    /// "oldest" would hand the top of the list to the least informative rows.
    func testUndatedGroupsGoLastInBothDirections() {
        let items = Fixtures.index([
            Fixtures.item("dated", bytes: 1_000, created: day(0)),
            Fixtures.item("dated-copy", bytes: 1_000, created: day(0)),
            Fixtures.item("undated", bytes: 9_000),
            Fixtures.item("undated-copy", bytes: 9_000)
        ])
        let candidates = [
            candidate("dated-copy", group: "g-dated", keeper: "dated", bytes: 1_000),
            candidate("undated-copy", group: "g-undated", keeper: "undated", bytes: 9_000)
        ]

        for order in [ReviewBuilder.Order.oldest, .newest] {
            let sections = ReviewBuilder.sections(candidates: candidates, items: items, order: order)
            XCTAssertEqual(
                sections.first?.groups.map(\.keeper.id),
                ["dated", "undated"],
                "an undated group came first under \(order)"
            )
        }
    }

    /// Without a tie-break, two groups of the same size — the common case for a burst — could
    /// swap places between two reads of the same data, and the list would shuffle under the
    /// finger of someone ticking through it.
    func testTheOrderIsStableAcrossReads() {
        let items = Fixtures.index((0..<6).map { Fixtures.item("item-\($0)", bytes: 4_000, created: day(5)) })
        let candidates = (0..<3).map {
            candidate("item-\($0 * 2 + 1)", group: "g\($0)", keeper: "item-\($0 * 2)", bytes: 4_000)
        }

        for order in ReviewBuilder.Order.allCases {
            let first = ReviewBuilder.sections(candidates: candidates, items: items, order: order)
            let second = ReviewBuilder.sections(candidates: candidates, items: items, order: order)
            XCTAssertEqual(
                first.first?.groups.map(\.id),
                second.first?.groups.map(\.id),
                "\(order) is not stable"
            )
        }
    }

    /// Changing the order may not change what is on offer — only where to start looking.
    func testOrderingNeverChangesWhatIsOffered() {
        let (items, candidates) = fixture()
        let reference = Set(
            ReviewBuilder.sections(candidates: candidates, items: items)
                .flatMap(\.groups)
                .flatMap(\.candidateIDs)
        )

        for order in ReviewBuilder.Order.allCases {
            let offered = Set(
                ReviewBuilder.sections(candidates: candidates, items: items, order: order)
                    .flatMap(\.groups)
                    .flatMap(\.candidateIDs)
            )
            XCTAssertEqual(offered, reference, "\(order) changed what is on offer")
        }
    }
}
