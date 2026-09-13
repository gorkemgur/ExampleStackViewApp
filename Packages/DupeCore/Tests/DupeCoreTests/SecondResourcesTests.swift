import XCTest
@testable import DupeCore

/// The weight nobody can account for and nobody can remove.
///
/// A Live Photo carries about three seconds of video beside the still; a RAW+JPEG asset carries
/// a whole second photograph. Neither can be deleted on its own — `PHAssetChangeRequest` has no
/// request for it — so the only honest thing the app can do is say what they cost. These are the
/// tests for the saying.
final class SecondResourcesTests: XCTestCase {

    func testAnOrdinaryLibraryHasNothingToReport() {
        let plain = SecondResources.tally([
            Fixtures.item("one"),
            Fixtures.item("two"),
            Fixtures.item("three", kind: .video)
        ])
        XCTAssertTrue(plain.isEmpty)
        XCTAssertEqual(plain.totalBytes, 0)
    }

    func testLivePhotoVideoIsCountedOnceEach() {
        let tally = SecondResources.tally([
            Fixtures.item("live-1", pairedVideoBytes: 3_000_000, live: true),
            Fixtures.item("live-2", pairedVideoBytes: 4_500_000, live: true),
            Fixtures.item("still", pairedVideoBytes: 0)
        ])
        XCTAssertEqual(tally.livePhotoCount, 2)
        XCTAssertEqual(tally.livePhotoVideoBytes, 7_500_000)
        XCTAssertEqual(tally.rawCount, 0)
    }

    func testTheRawHalfIsCounted() {
        let tally = SecondResources.tally([
            Fixtures.item("proraw-1", bytes: 3_000_000, alternatePhotoBytes: 48_000_000),
            Fixtures.item("proraw-2", bytes: 3_200_000, alternatePhotoBytes: 51_000_000)
        ])
        XCTAssertEqual(tally.rawCount, 2)
        XCTAssertEqual(tally.rawBytes, 99_000_000)
        XCTAssertFalse(tally.isEmpty)
    }

    /// One asset can be both, and each half is counted under its own name rather than once
    /// under whichever was noticed first.
    func testAnAssetCanCarryBoth() {
        let tally = SecondResources.tally([
            Fixtures.item("both", pairedVideoBytes: 3_000_000, alternatePhotoBytes: 40_000_000, live: true)
        ])
        XCTAssertEqual(tally.livePhotoCount, 1)
        XCTAssertEqual(tally.rawCount, 1)
        XCTAssertEqual(tally.totalBytes, 43_000_000)
    }

    /// THE FLAG IS NOT THE EVIDENCE. `isLivePhoto` comes from a media subtype and the paired
    /// video comes from a resource that may not be on this device — an asset in iCloud can say
    /// it is a Live Photo while its video half has never been measured here. Counting the flag
    /// would put a number on the screen with nothing behind it, which is the failure mode this
    /// whole project keeps finding: a claim printed whether or not it is true.
    func testAnAssetThatSaysItIsLiveButHasNoMeasuredVideoIsNotCounted() {
        let tally = SecondResources.tally([
            Fixtures.item("claims-to-be-live", pairedVideoBytes: 0, live: true, local: false)
        ])
        XCTAssertEqual(tally.livePhotoCount, 0)
        XCTAssertTrue(tally.isEmpty)
    }
}
