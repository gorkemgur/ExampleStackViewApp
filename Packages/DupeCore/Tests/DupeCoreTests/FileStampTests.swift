import XCTest
@testable import DupeCore

final class FileStampTests: XCTestCase {

    private let when = Date(timeIntervalSince1970: 1_700_000_000)

    func testTheSameFileMatches() {
        let stamp = FileStamp(byteSize: 1_024, modificationDate: when)
        XCTAssertTrue(stamp.matches(byteSize: 1_024, modificationDate: when))
    }

    func testADifferentSizeIsADifferentFile() {
        let stamp = FileStamp(byteSize: 1_024, modificationDate: when)
        XCTAssertFalse(stamp.matches(byteSize: 1_025, modificationDate: when))
    }

    func testAFileRewrittenInPlaceIsCaughtByItsTimestamp() {
        let stamp = FileStamp(byteSize: 1_024, modificationDate: when)
        XCTAssertFalse(
            stamp.matches(byteSize: 1_024, modificationDate: when.addingTimeInterval(60)),
            "same length, different content, written later"
        )
    }

    /// Timestamps come back with sub-second noise depending on which API produced them, and a
    /// deletion refused over a rounding error is a bug of its own.
    func testSubSecondNoiseIsNotAChange() {
        let stamp = FileStamp(byteSize: 10, modificationDate: when)
        XCTAssertTrue(stamp.matches(byteSize: 10, modificationDate: when.addingTimeInterval(0.4)))
        XCTAssertTrue(stamp.matches(byteSize: 10, modificationDate: when.addingTimeInterval(-0.9)))
        XCTAssertFalse(stamp.matches(byteSize: 10, modificationDate: when.addingTimeInterval(2)))
    }

    /// One side knowing a date and the other not is a different answer, not the same one — and
    /// this decides whether something is destroyed.
    func testAMissingDateOnOneSideIsNotAMatch() {
        XCTAssertFalse(
            FileStamp(byteSize: 10, modificationDate: when).matches(byteSize: 10, modificationDate: nil)
        )
        XCTAssertFalse(
            FileStamp(byteSize: 10, modificationDate: nil).matches(byteSize: 10, modificationDate: when)
        )
        XCTAssertTrue(
            FileStamp(byteSize: 10, modificationDate: nil).matches(byteSize: 10, modificationDate: nil)
        )
    }

    func testItIsBuiltFromTheItemTheScanRead() {
        let item = MediaItem(
            id: "file:x",
            source: .fileFolder,
            kind: .document,
            displayName: "x.pdf",
            byteSize: 4_096,
            modificationDate: when
        )
        XCTAssertEqual(FileStamp(item), FileStamp(byteSize: 4_096, modificationDate: when))
    }
}
