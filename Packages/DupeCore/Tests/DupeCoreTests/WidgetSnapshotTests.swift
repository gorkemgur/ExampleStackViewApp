import XCTest
@testable import DupeCore

final class WidgetSnapshotTests: XCTestCase {

    func testUsedCapacityAndFraction() {
        let snapshot = WidgetSnapshot(totalCapacity: 200, availableCapacity: 50)
        XCTAssertEqual(snapshot.usedCapacity, 150)
        XCTAssertEqual(snapshot.usedFraction, 0.75, accuracy: 0.0001)
    }

    func testValuesAreClampedIntoSomethingRenderable() {
        let overreported = WidgetSnapshot(totalCapacity: 100, availableCapacity: 500)
        XCTAssertEqual(overreported.availableCapacity, 100)
        XCTAssertEqual(overreported.usedCapacity, 0)

        let negative = WidgetSnapshot(totalCapacity: -5, availableCapacity: -5)
        XCTAssertEqual(negative.totalCapacity, 0)
        XCTAssertEqual(negative.usedFraction, 0, "an empty volume must not divide by zero")
    }

    func testLosslessBytesCannotExceedWhatWasFound() {
        let snapshot = WidgetSnapshot(
            totalCapacity: 100,
            availableCapacity: 10,
            reclaimableBytes: 5,
            losslessBytes: 900
        )
        XCTAssertEqual(snapshot.losslessBytes, 5)
    }

    func testProjectionStopsAtAFullDisk() {
        let snapshot = WidgetSnapshot(
            totalCapacity: 100,
            availableCapacity: 90,
            reclaimableBytes: 50
        )
        XCTAssertEqual(snapshot.projectedAvailableCapacity, 100)
    }

    func testHasScannedOnlyOnceSomethingHasRun() {
        XCTAssertFalse(WidgetSnapshot(totalCapacity: 1, availableCapacity: 1).hasScanned)
        XCTAssertTrue(
            WidgetSnapshot(totalCapacity: 1, availableCapacity: 1, lastScanAt: Date()).hasScanned
        )
    }

    /// A widget with nothing to show must not render as a full disk.
    func testThePlaceholderLooksLikeARealDevice() {
        let placeholder = WidgetSnapshot.placeholder
        XCTAssertGreaterThan(placeholder.totalCapacity, 0)
        XCTAssertGreaterThan(placeholder.availableCapacity, 0)
        XCTAssertLessThan(placeholder.usedFraction, 1)
        XCTAssertTrue(placeholder.hasScanned)
    }
}

final class WidgetSnapshotStoreTests: XCTestCase {

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-\(UUID().uuidString).json")
    }

    func testWhatTheAppWritesIsWhatTheWidgetReads() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = WidgetSnapshot(
            totalCapacity: 512_000_000_000,
            availableCapacity: 40_000_000_000,
            libraryBytes: 90_000_000_000,
            reclaimableBytes: 8_000_000_000,
            duplicateCount: 214,
            losslessBytes: 6_000_000_000,
            lastScanAt: Date(timeIntervalSince1970: 1_000),
            lifetimeReclaimedBytes: 22_000_000_000,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        WidgetSnapshotStore(fileURL: url).write(snapshot)
        XCTAssertEqual(WidgetSnapshotStore(fileURL: url).read(), snapshot)
    }

    func testNothingWrittenYetReadsAsNothing() {
        XCTAssertNil(WidgetSnapshotStore(fileURL: temporaryURL()).read())
    }

    func testACorruptFileReadsAsNothingRatherThanCrashingTheWidget() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data("not json".utf8).write(to: url)

        XCTAssertNil(WidgetSnapshotStore(fileURL: url).read())
    }

    func testWritingReplacesTheWholeSnapshot() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WidgetSnapshotStore(fileURL: url)

        store.write(WidgetSnapshot(totalCapacity: 100, availableCapacity: 10, duplicateCount: 5))
        store.write(WidgetSnapshot(totalCapacity: 100, availableCapacity: 20))

        XCTAssertEqual(store.read()?.duplicateCount, 0)
        XCTAssertEqual(store.read()?.availableCapacity, 20)
    }

    func testAnUnavailableAppGroupIsNotAStore() {
        XCTAssertNil(WidgetSnapshotStore(appGroupID: "group.this.does.not.exist.anywhere"))
    }
}

final class WidgetSnapshotUpdateTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 9_000)

    private var existing: WidgetSnapshot {
        WidgetSnapshot(
            totalCapacity: 100,
            availableCapacity: 20,
            libraryBytes: 50,
            reclaimableBytes: 8,
            duplicateCount: 4,
            losslessBytes: 6,
            lastScanAt: Date(timeIntervalSince1970: 1_000),
            lifetimeReclaimedBytes: 70,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    func testAnUpdateOnlyChangesWhatItCarries() {
        let updated = WidgetSnapshotUpdate(availableCapacity: 30).applied(to: existing, now: now)

        XCTAssertEqual(updated.availableCapacity, 30)
        XCTAssertEqual(updated.libraryBytes, existing.libraryBytes)
        XCTAssertEqual(updated.reclaimableBytes, existing.reclaimableBytes)
        XCTAssertEqual(updated.duplicateCount, existing.duplicateCount)
        XCTAssertEqual(updated.lifetimeReclaimedBytes, existing.lifetimeReclaimedBytes)
        XCTAssertEqual(updated.lastScanAt, existing.lastScanAt, "refreshing capacity is not a scan")
        XCTAssertEqual(updated.updatedAt, now)
    }

    func testOnlyACompletedScanStampsTheScanTime() {
        let refreshed = WidgetSnapshotUpdate(libraryBytes: 60).applied(to: existing, now: now)
        XCTAssertEqual(refreshed.lastScanAt, existing.lastScanAt)

        let scanned = WidgetSnapshotUpdate(
            reclaimableBytes: 12,
            duplicateCount: 9,
            losslessBytes: 10,
            markScanned: true
        ).applied(to: existing, now: now)

        XCTAssertEqual(scanned.lastScanAt, now)
        XCTAssertEqual(scanned.reclaimableBytes, 12)
        XCTAssertEqual(scanned.duplicateCount, 9)
    }

    func testAScanThatFoundNothingSaysSoRatherThanKeepingTheOldNumber() {
        let scanned = WidgetSnapshotUpdate(
            reclaimableBytes: 0,
            duplicateCount: 0,
            losslessBytes: 0,
            markScanned: true
        ).applied(to: existing, now: now)

        XCTAssertEqual(scanned.reclaimableBytes, 0, "a stale 8 bytes would be a lie")
        XCTAssertEqual(scanned.duplicateCount, 0)
    }

    func testAnUpdateWithNothingBeforeItStillProducesSomethingRenderable() {
        let fresh = WidgetSnapshotUpdate(totalCapacity: 100, availableCapacity: 40)
            .applied(to: nil, now: now)

        XCTAssertEqual(fresh.totalCapacity, 100)
        XCTAssertEqual(fresh.availableCapacity, 40)
        XCTAssertFalse(fresh.hasScanned)
        XCTAssertEqual(fresh.reclaimableBytes, 0)
    }
}
