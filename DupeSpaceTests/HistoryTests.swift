import XCTest
import DupeCore
@testable import DupeSpace

@MainActor
final class HistoryViewModelTests: XCTestCase {

    private func scanRecord(_ offset: TimeInterval = 0) -> ScanRecord {
        let start = Date(timeIntervalSince1970: 2_000 + offset)
        return ScanRecord(
            startedAt: start,
            finishedAt: start.addingTimeInterval(5),
            itemsScanned: 10,
            groupsFound: 2,
            reclaimableBytes: 1_234,
            tiers: [],
            cloudOnlyCount: 0
        )
    }

    private func deletionRecord() -> DeletionRecord {
        DeletionRecord(
            performedAt: Date(timeIntervalSince1970: 3_000),
            items: [
                DeletedItemRecord(
                    id: "a", displayName: "IMG_1.HEIC", bytes: 500,
                    kind: .image, tier: .identical, keptInsteadName: "IMG_0.HEIC"
                )
            ],
            deferredBytes: 500,
            immediateBytes: 0
        )
    }

    /// The store writes on a detached task, so tests wait for it rather than guessing.
    private func waitForSave(_ store: InMemoryHistoryStore, atLeast count: Int) async {
        let deadline = Date().addingTimeInterval(5)
        while store.saveCount < count && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testStartsEmptyAndLoadsWhatWasSaved() async {
        var seeded = HistoryLog()
        seeded.record(scanRecord())

        let model = HistoryViewModel(store: InMemoryHistoryStore(log: seeded))
        XCTAssertTrue(model.isEmpty, "nothing is shown before the log is read")

        await model.load()
        XCTAssertFalse(model.isEmpty)
        XCTAssertEqual(model.timeline.count, 1)
    }

    func testLoadingTwiceDoesNotDiscardNewerRecords() async {
        let model = HistoryViewModel(store: InMemoryHistoryStore())
        await model.load()
        model.record(scan: scanRecord())

        await model.load()
        XCTAssertEqual(model.timeline.count, 1, "a second load must not wipe what just happened")
    }

    func testRecordingPersists() async {
        let store = InMemoryHistoryStore()
        let model = HistoryViewModel(store: store)
        await model.load()

        model.record(deletion: deletionRecord())
        await waitForSave(store, atLeast: 1)

        let saved = await store.load()
        XCTAssertEqual(saved.totalItemsDeleted, 1)
        XCTAssertEqual(saved.totalReclaimedBytes, 500)
    }

    func testTotalsAndRecoverableDeletions() async {
        let model = HistoryViewModel(store: InMemoryHistoryStore())
        await model.load()
        model.record(deletion: deletionRecord())

        XCTAssertEqual(model.totalItemsDeleted, 1)
        XCTAssertEqual(model.totalReclaimedBytes, 500)
        XCTAssertEqual(model.recoverableDeletions(at: Date(timeIntervalSince1970: 3_060)).count, 1)
        XCTAssertTrue(
            model.recoverableDeletions(at: Date(timeIntervalSince1970: 3_000 + 40 * 86_400)).isEmpty
        )
    }

    func testClearingPersistsTheEmptyLog() async {
        let store = InMemoryHistoryStore()
        let model = HistoryViewModel(store: store)
        await model.load()
        model.record(scan: scanRecord())
        await waitForSave(store, atLeast: 1)

        model.clear()
        await waitForSave(store, atLeast: 2)

        XCTAssertTrue(model.isEmpty)
        let saved = await store.load()
        XCTAssertTrue(saved.isEmpty)
    }
}

final class FileHistoryStoreTests: XCTestCase {

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
    }

    func testRoundTripsThroughDisk() async {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        var log = HistoryLog()
        log.record(
            DeletionRecord(
                performedAt: Date(timeIntervalSince1970: 10),
                items: [
                    DeletedItemRecord(
                        id: "x", displayName: "x.HEIC", bytes: 7,
                        kind: .image, tier: .inferiorCopy, keptInsteadName: "y.HEIC"
                    )
                ],
                deferredBytes: 7,
                immediateBytes: 0
            )
        )

        let store = FileHistoryStore(fileURL: url)
        await store.save(log)
        let restored = await store.load()

        XCTAssertEqual(restored, log)
        XCTAssertEqual(restored.deletions.first?.items.first?.keptInsteadName, "y.HEIC")
    }

    func testAMissingFileReadsAsNoHistory() async {
        let store = FileHistoryStore(fileURL: temporaryURL())
        let loaded = await store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    /// Failing to read the receipt must never stop someone using the app the receipt is about.
    func testACorruptFileReadsAsNoHistoryRatherThanCrashing() async {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data("this is not json".utf8).write(to: url)

        let loaded = await FileHistoryStore(fileURL: url).load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSavingOverwritesRatherThanAppending() async {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileHistoryStore(fileURL: url)

        var first = HistoryLog()
        first.record(
            ScanRecord(
                startedAt: .init(timeIntervalSince1970: 1), finishedAt: .init(timeIntervalSince1970: 2),
                itemsScanned: 1, groupsFound: 0, reclaimableBytes: 0, tiers: [], cloudOnlyCount: 0
            )
        )
        await store.save(first)
        await store.save(HistoryLog())

        XCTAssertTrue(await store.load().isEmpty)
    }
}
