import XCTest
import DupeCore
@testable import DupeSpace

final class StorageProbeTests: XCTestCase {

    func testProbeReadsTheVolume() throws {
        let snapshot = try XCTUnwrap(StorageProbe.current(), "volume capacity keys returned nothing")
        XCTAssertGreaterThan(snapshot.totalCapacity, 0)
        XCTAssertLessThanOrEqual(snapshot.availableCapacity, snapshot.totalCapacity)
        XCTAssertEqual(snapshot.usedCapacity, snapshot.totalCapacity - snapshot.availableCapacity)
    }

    func testByteFormattingIsHumanReadable() {
        XCTAssertFalse(ByteFormatting.string(1_500_000_000).isEmpty)
        XCTAssertFalse(ByteFormatting.string(-5).isEmpty, "negative input must not crash or blank out")
    }

    func testCountingAgreesWithItsNoun() {
        XCTAssertEqual(Counting.items(0), "0 items")
        XCTAssertEqual(Counting.items(1), "1 item")
        XCTAssertEqual(Counting.items(2), "2 items")
        XCTAssertEqual(Counting.copies(1), "1 other copy")
        XCTAssertEqual(Counting.copies(3), "3 other copies")
    }

    func testZeroIsWrittenAsANumber() {
        // ByteCountFormatter says "Zero KB" by default, which reads like a bug in the app.
        XCTAssertFalse(ByteFormatting.string(0).localizedCaseInsensitiveContains("zero"))
        XCTAssertTrue(ByteFormatting.string(0).contains("0"))
    }
}
