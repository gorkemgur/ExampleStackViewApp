import XCTest
@testable import DupeCore

final class HistoryLogTests: XCTestCase {

    private func scan(_ offset: TimeInterval, groups: Int = 1) -> ScanRecord {
        let start = Date(timeIntervalSince1970: 1_000_000 + offset)
        return ScanRecord(
            startedAt: start,
            finishedAt: start.addingTimeInterval(12),
            itemsScanned: 100,
            groupsFound: groups,
            reclaimableBytes: 5_000,
            tiers: [TierTotal(tier: .identical, itemCount: 1, bytes: 5_000)],
            cloudOnlyCount: 0
        )
    }

    private func deletion(_ offset: TimeInterval, bytes: Int64 = 1_000, deferred: Bool = true) -> DeletionRecord {
        DeletionRecord(
            performedAt: Date(timeIntervalSince1970: 1_000_000 + offset),
            items: [
                DeletedItemRecord(
                    id: "i\(offset)",
                    displayName: "IMG.HEIC",
                    bytes: bytes,
                    kind: .image,
                    tier: .identical,
                    keptInsteadName: "IMG_ORIGINAL.HEIC"
                )
            ],
            deferredBytes: deferred ? bytes : 0,
            immediateBytes: deferred ? 0 : bytes
        )
    }

    func testStartsEmpty() {
        XCTAssertTrue(HistoryLog().isEmpty)
        XCTAssertTrue(HistoryLog().timeline.isEmpty)
        XCTAssertEqual(HistoryLog().totalReclaimedBytes, 0)
    }

    func testTimelineIsNewestFirstAndInterleaved() {
        var log = HistoryLog()
        log.record(scan(0))
        log.record(deletion(50))
        log.record(scan(100))

        let dates = log.timeline.map(\.date)
        XCTAssertEqual(dates, dates.sorted(by: >))
        if case .scan = log.timeline[0] {} else { XCTFail("newest entry should be the last scan") }
    }

    func testTimelineOrderIsStableForSimultaneousEntries() {
        var log = HistoryLog()
        log.record(scan(0))
        log.record(deletion(-12))  // same instant as the scan's finishedAt

        let first = log.timeline.map(\.id)
        let second = log.timeline.map(\.id)
        XCTAssertEqual(first, second)
    }

    func testTotalsAddUpAcrossDeletions() {
        var log = HistoryLog()
        log.record(deletion(0, bytes: 1_000))
        log.record(deletion(10, bytes: 2_500))

        XCTAssertEqual(log.totalReclaimedBytes, 3_500)
        XCTAssertEqual(log.totalItemsDeleted, 2)
    }

    func testScansAreCappedKeepingTheNewest() {
        var log = HistoryLog()
        for index in 0..<(HistoryLog.maximumScans + 10) {
            log.record(scan(TimeInterval(index)))
        }
        XCTAssertEqual(log.scans.count, HistoryLog.maximumScans)
        XCTAssertEqual(log.scans.first?.startedAt, scan(TimeInterval(HistoryLog.maximumScans + 9)).startedAt)
    }

    func testDeletionsAreCappedKeepingTheNewest() {
        var log = HistoryLog()
        for index in 0..<(HistoryLog.maximumDeletions + 5) {
            log.record(deletion(TimeInterval(index)))
        }
        XCTAssertEqual(log.deletions.count, HistoryLog.maximumDeletions)
    }

    func testClear() {
        var log = HistoryLog()
        log.record(scan(0))
        log.record(deletion(0))
        log.clear()
        XCTAssertTrue(log.isEmpty)
    }

    func testRoundTripsThroughJSON() throws {
        var log = HistoryLog()
        log.record(scan(0))
        log.record(deletion(20))

        let data = try JSONEncoder().encode(log)
        let restored = try JSONDecoder().decode(HistoryLog.self, from: data)
        XCTAssertEqual(restored, log)
    }

    func testAnOlderFileIsAcceptedAndReSorted() throws {
        // Records written in any order must come back newest-first.
        let log = HistoryLog(scans: [scan(0), scan(500), scan(100)], deletions: [])
        XCTAssertEqual(log.scans.map(\.startedAt), log.scans.map(\.startedAt).sorted(by: >))
    }
}

final class DeletionRecoveryTests: XCTestCase {

    private let performedAt = Date(timeIntervalSince1970: 1_000_000)

    private func record(deferred: Int64, immediate: Int64) -> DeletionRecord {
        DeletionRecord(
            performedAt: performedAt,
            items: [],
            deferredBytes: deferred,
            immediateBytes: immediate
        )
    }

    func testPhotoDeletionsAreRecoverableForThirtyDays() {
        let deletion = record(deferred: 1_000, immediate: 0)
        XCTAssertEqual(deletion.recoverableUntil, performedAt.addingTimeInterval(30 * 24 * 60 * 60))
        XCTAssertTrue(deletion.isStillRecoverable(at: performedAt.addingTimeInterval(29 * 24 * 60 * 60)))
        XCTAssertFalse(deletion.isStillRecoverable(at: performedAt.addingTimeInterval(31 * 24 * 60 * 60)))
    }

    func testFileDeletionsAreNeverRecoverable() {
        let deletion = record(deferred: 0, immediate: 1_000)
        XCTAssertNil(deletion.recoverableUntil, "nothing went to Recently Deleted, so nothing can come back")
        XCTAssertFalse(deletion.isStillRecoverable(at: performedAt))
    }

    func testExactlyAtTheDeadlineIsNoLongerRecoverable() {
        let deletion = record(deferred: 1, immediate: 0)
        XCTAssertFalse(deletion.isStillRecoverable(at: deletion.recoverableUntil!))
    }

    func testLogListsOnlyWhatCanStillComeBack() {
        var log = HistoryLog()
        log.record(DeletionRecord(performedAt: performedAt, items: [], deferredBytes: 10, immediateBytes: 0))
        log.record(
            DeletionRecord(
                performedAt: performedAt.addingTimeInterval(-60 * 24 * 60 * 60),
                items: [],
                deferredBytes: 10,
                immediateBytes: 0
            )
        )
        XCTAssertEqual(log.recoverableDeletions(at: performedAt.addingTimeInterval(60)).count, 1)
    }

    func testJudgementCallsAreCounted() {
        let deletion = DeletionRecord(
            performedAt: performedAt,
            items: [
                DeletedItemRecord(id: "a", displayName: "a", bytes: 1, kind: .image, tier: .identical, keptInsteadName: "k"),
                DeletedItemRecord(id: "b", displayName: "b", bytes: 1, kind: .image, tier: .burstLeftover, keptInsteadName: "k"),
                DeletedItemRecord(id: "c", displayName: "c", bytes: 1, kind: .image, tier: .similar, keptInsteadName: "k")
            ],
            deferredBytes: 3,
            immediateBytes: 0
        )
        XCTAssertEqual(deletion.judgementCallCount, 2)
        XCTAssertEqual(deletion.itemCount, 3)
    }
}

final class HistoryBuilderTests: XCTestCase {

    private func result() -> ScanResult {
        let items = Fixtures.index([
            Fixtures.item("keeper", bytes: 9_000_000),
            Fixtures.item("copy", bytes: 9_000_000),
            Fixtures.item("similar", bytes: 400_000)
        ])
        let candidates = [
            DeletionCandidate(id: "copy", groupID: "g", keeperID: "keeper", tier: .identical, bytes: 9_000_000, isPreSelected: true),
            DeletionCandidate(id: "similar", groupID: "g2", keeperID: "keeper", tier: .similar, bytes: 400_000, isPreSelected: false)
        ]
        return ScanResult(
            items: items,
            groups: [DuplicateGroup(id: "g", relation: .exact, seedID: "keeper", itemIDs: ["keeper", "copy"])],
            decisions: [],
            candidates: candidates,
            cloudOnlyIDs: ["ghost"]
        )
    }

    func testScanRecordCapturesWhatWasFound() {
        let start = Date(timeIntervalSince1970: 1_000)
        let record = HistoryBuilder.scanRecord(
            result: result(),
            itemsScanned: 42,
            startedAt: start,
            finishedAt: start.addingTimeInterval(9)
        )

        XCTAssertEqual(record.itemsScanned, 42)
        XCTAssertEqual(record.groupsFound, 1)
        XCTAssertEqual(record.reclaimableBytes, 9_400_000)
        XCTAssertEqual(record.cloudOnlyCount, 1)
        XCTAssertEqual(record.duration, 9)
        XCTAssertEqual(record.tiers.map(\.tier), [.identical, .similar])
        XCTAssertTrue(record.foundSomething)
    }

    func testDeletionRecordNamesWhatWasKeptInstead() {
        let scan = result()
        let savings = SavingsCalculator.breakdown(for: ["copy"], items: scan.items)
        let record = HistoryBuilder.deletionRecord(
            deletedIDs: ["copy"],
            result: scan,
            savings: savings,
            performedAt: Date(timeIntervalSince1970: 5_000)
        )

        XCTAssertEqual(record.items.count, 1)
        XCTAssertEqual(record.items[0].keptInsteadName, "keeper")
        XCTAssertEqual(record.items[0].tier, .identical)
        XCTAssertEqual(record.reclaimedBytes, 9_000_000)
        XCTAssertEqual(record.judgementCallCount, 0)
    }

    func testDeletionRecordIsOrderIndependent() {
        let scan = result()
        let savings = SavingsCalculator.breakdown(for: ["copy", "similar"], items: scan.items)
        let forward = HistoryBuilder.deletionRecord(
            deletedIDs: ["copy", "similar"], result: scan, savings: savings, performedAt: .init()
        )
        let backward = HistoryBuilder.deletionRecord(
            deletedIDs: ["similar", "copy"], result: scan, savings: savings, performedAt: .init()
        )
        XCTAssertEqual(forward.items.map(\.id), backward.items.map(\.id))
    }

    func testItemsMissingFromTheIndexAreSkipped() {
        let scan = result()
        let record = HistoryBuilder.deletionRecord(
            deletedIDs: ["ghost"],
            result: scan,
            savings: .empty,
            performedAt: .init()
        )
        XCTAssertTrue(record.items.isEmpty)
    }

    func testAnItemWithNoMatchingCandidateStillGetsAReceipt() {
        let scan = result()
        let record = HistoryBuilder.deletionRecord(
            deletedIDs: ["keeper"],
            result: scan,
            savings: .empty,
            performedAt: .init()
        )
        XCTAssertEqual(record.items.first?.keptInsteadName, "another copy")
    }
}
