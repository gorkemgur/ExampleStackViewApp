import XCTest
@testable import DupeCore

final class StorageSnapshotTests: XCTestCase {

    func testUsedCapacityAndFraction() {
        let snapshot = StorageSnapshot(totalCapacity: 128_000_000_000, availableCapacity: 32_000_000_000)
        XCTAssertEqual(snapshot.usedCapacity, 96_000_000_000)
        XCTAssertEqual(snapshot.usedFraction, 0.75, accuracy: 0.0001)
    }

    func testAvailableIsClampedIntoRange() {
        let overreported = StorageSnapshot(totalCapacity: 100, availableCapacity: 500)
        XCTAssertEqual(overreported.availableCapacity, 100)
        XCTAssertEqual(overreported.usedCapacity, 0)

        let negative = StorageSnapshot(totalCapacity: 100, availableCapacity: -20)
        XCTAssertEqual(negative.availableCapacity, 0)
    }

    func testEmptyVolumeDoesNotDivideByZero() {
        XCTAssertEqual(StorageSnapshot(totalCapacity: 0, availableCapacity: 0).usedFraction, 0)
    }

    func testProjectionAddsReclaimedSpace() {
        let before = StorageSnapshot(totalCapacity: 1000, availableCapacity: 100)
        let after = before.projecting(reclaimed: 250)
        XCTAssertEqual(after.availableCapacity, 350)
        XCTAssertEqual(after.totalCapacity, 1000)
    }

    func testProjectionCannotExceedTheVolume() {
        let before = StorageSnapshot(totalCapacity: 1000, availableCapacity: 900)
        XCTAssertEqual(before.projecting(reclaimed: 5000).availableCapacity, 1000)
    }
}
