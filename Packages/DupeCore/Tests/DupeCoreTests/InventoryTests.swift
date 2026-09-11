import XCTest
@testable import DupeCore

final class InventoryAnalyzerTests: XCTestCase {

    private var library: [MediaItem] {
        [
            Fixtures.item("photo1", kind: .image, bytes: 3_000_000),
            Fixtures.item("photo2", kind: .image, bytes: 2_000_000),
            Fixtures.item("video1", kind: .video, bytes: 400_000_000),
            Fixtures.item("shot1", kind: .image, bytes: 500_000, screenshot: true),
            Fixtures.item("live1", kind: .image, bytes: 2_000_000, pairedVideoBytes: 4_000_000, live: true),
            Fixtures.item("doc1", source: .fileFolder, kind: .document, bytes: 900_000)
        ]
    }

    func testEveryItemLandsInExactlyOneBucket() {
        let breakdown = InventoryAnalyzer.breakdown(for: library)
        XCTAssertEqual(breakdown.reduce(0) { $0 + $1.itemCount }, library.count)
        XCTAssertEqual(
            breakdown.reduce(Int64(0)) { $0 + $1.bytes },
            InventoryAnalyzer.totalBytes(library),
            "category totals must add up to the library total"
        )
    }

    func testCategoryPrecedence() {
        XCTAssertEqual(InventoryAnalyzer.category(for: library[3]), .screenshots)
        XCTAssertEqual(InventoryAnalyzer.category(for: library[4]), .livePhotos)
        XCTAssertEqual(InventoryAnalyzer.category(for: library[2]), .videos)
        XCTAssertEqual(InventoryAnalyzer.category(for: library[5]), .documents)
        XCTAssertEqual(InventoryAnalyzer.category(for: library[0]), .photos)
    }

    func testAVideoScreenshotIsCountedAsAVideo() {
        // A screen recording is a video, not a screenshot, and must not be double counted.
        let recording = Fixtures.item("rec", kind: .video, bytes: 10, screenshot: true)
        XCTAssertEqual(InventoryAnalyzer.category(for: recording), .videos)
    }

    func testLivePhotoBytesIncludeThePairedMovie() {
        let breakdown = InventoryAnalyzer.breakdown(for: library)
        let live = breakdown.first { $0.category == .livePhotos }
        XCTAssertEqual(live?.bytes, 6_000_000)
    }

    func testBreakdownIsOrderedByCost() {
        let breakdown = InventoryAnalyzer.breakdown(for: library)
        XCTAssertEqual(breakdown.first?.category, .videos)
        XCTAssertEqual(breakdown.map(\.bytes), breakdown.map(\.bytes).sorted(by: >))
    }

    func testLargestItems() {
        let largest = InventoryAnalyzer.largest(library, limit: 2)
        XCTAssertEqual(largest.map(\.id), ["video1", "live1"])
        XCTAssertTrue(InventoryAnalyzer.largest(library, limit: 0).isEmpty)
        XCTAssertEqual(InventoryAnalyzer.largest(library, limit: 100).count, library.count)
    }

    func testCloudOnlyBytesAreReportedSeparately() {
        let items = [
            Fixtures.item("local", bytes: 100),
            Fixtures.item("cloud", bytes: 900, local: false)
        ]
        XCTAssertEqual(InventoryAnalyzer.cloudOnlyBytes(items), 900)
    }

    func testEmptyLibrary() {
        XCTAssertTrue(InventoryAnalyzer.breakdown(for: []).isEmpty)
        XCTAssertEqual(InventoryAnalyzer.totalBytes([]), 0)
    }
}
