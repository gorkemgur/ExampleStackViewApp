import XCTest
@testable import DupeCore

/// The heat map is evidence for a deletion, so the arithmetic behind it is the part that
/// matters. A picture that says two copies differ where they do not is worse than no picture.
final class DifferenceGridTests: XCTestCase {

    private func image(_ width: Int, _ height: Int, _ value: (Int, Int) -> UInt8) -> GrayImage {
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(value(x, y))
            }
        }
        return GrayImage(width: width, height: height, pixels: pixels)!
    }

    func testTwoIdenticalCopiesHaveNothingToShow() {
        let a = image(64, 64) { x, _ in UInt8(x * 4 % 256) }
        let grid = DifferenceGrid.between(a, a, size: 8)

        XCTAssertEqual(grid?.peak, 0)
        XCTAssertTrue(grid?.isBelowNoiseFloor ?? false)
        XCTAssertTrue(grid?.cells.allSatisfy { $0 == 0 } ?? false)
    }

    /// The whole point: the hot cell has to be where the difference actually is.
    func testTheDifferenceLandsInTheRightCell() {
        let plain = image(64, 64) { _, _ in 0 }
        // One bright block in the bottom-right eighth.
        let marked = image(64, 64) { x, y in (x >= 56 && y >= 56) ? 255 : 0 }

        guard let grid = DifferenceGrid.between(plain, marked, size: 8) else {
            return XCTFail("no grid")
        }

        XCTAssertEqual(grid.cell(x: 7, y: 7), 1, accuracy: 0.0001, "the hot cell is not where the change is")
        for y in 0..<8 {
            for x in 0..<8 where !(x == 7 && y == 7) {
                XCTAssertEqual(grid.cell(x: x, y: y), 0, accuracy: 0.0001, "cell \(x),\(y) is hot and should not be")
            }
        }
    }

    /// Normalised to this pair's own peak, because the question is *where* the copy differs.
    /// How much it differs is the table's job, and the raw peak is carried for that.
    func testTheGridIsNormalisedButThePeakIsNot() {
        let plain = image(32, 32) { _, _ in 100 }
        let faint = image(32, 32) { x, y in (x >= 24 && y >= 24) ? 110 : 100 }

        guard let grid = DifferenceGrid.between(plain, faint, size: 4) else {
            return XCTFail("no grid")
        }

        XCTAssertEqual(grid.cell(x: 3, y: 3), 1, accuracy: 0.0001, "a faint difference still reads as this pair's maximum")
        XCTAssertEqual(grid.peak, 10.0 / 255, accuracy: 0.0001, "and the true magnitude survives beside it")
        XCTAssertFalse(grid.isBelowNoiseFloor)
    }

    /// A difference of one shade across a whole image is rounding, not evidence.
    func testRoundingErrorIsNotDrawn() {
        let a = image(64, 64) { _, _ in 128 }
        let b = image(64, 64) { _, _ in 130 }

        let grid = DifferenceGrid.between(a, b, size: 8)

        XCTAssertTrue(grid?.isBelowNoiseFloor ?? false, "two shades apart is not something to paint red")
    }

    func testMismatchedBuffersProduceNothingRatherThanNonsense() {
        let a = image(64, 64) { _, _ in 0 }
        let b = image(32, 32) { _, _ in 0 }

        XCTAssertNil(DifferenceGrid.between(a, b))
        XCTAssertNil(DifferenceGrid.between(a, a, size: 0))
    }

    /// Every cell is covered exactly once, whatever the grid size divides into.
    func testEveryPixelLandsInExactlyOneCell() {
        let plain = image(64, 64) { _, _ in 0 }
        let allWhite = image(64, 64) { _, _ in 255 }

        for size in [3, 5, 7, 16, 64] {
            guard let grid = DifferenceGrid.between(plain, allWhite, size: size) else {
                return XCTFail("no grid at size \(size)")
            }
            XCTAssertEqual(grid.cells.count, size * size)
            XCTAssertTrue(
                grid.cells.allSatisfy { abs($0 - 1) < 0.0001 },
                "a uniform difference must be uniform at size \(size)"
            )
            XCTAssertEqual(grid.peak, 1, accuracy: 0.0001)
        }
    }

    func testAskingOutsideTheGridIsZeroRatherThanACrash() {
        let grid = DifferenceGrid.between(
            image(8, 8) { _, _ in 0 },
            image(8, 8) { _, _ in 255 },
            size: 4
        )

        XCTAssertEqual(grid?.cell(x: -1, y: 0), 0)
        XCTAssertEqual(grid?.cell(x: 0, y: 99), 0)
    }
}
