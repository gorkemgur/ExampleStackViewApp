import XCTest
@testable import DupeCore

final class GrayImageTests: XCTestCase {

    func testResizeToSameSizeReturnsIdenticalBuffer() {
        let image = Fixtures.scene(width: 16, height: 16)
        XCTAssertEqual(image.resized(width: 16, height: 16), image)
    }

    func testDownscaleAveragesEverySourcePixel() {
        // 2x2 blocks of 0, 100, 200, 255 collapse to one pixel each.
        let image = Fixtures.image(width: 4, height: 4) { x, y in
            switch (x / 2, y / 2) {
            case (0, 0): return 0
            case (1, 0): return 100
            case (0, 1): return 200
            default: return 255
            }
        }
        let small = image.resized(width: 2, height: 2)
        XCTAssertEqual(small.pixels, [0, 100, 200, 255])
    }

    func testDownscaleCoversEverySourceRowAndColumn() {
        // A single bright pixel must still influence the average it falls into.
        let image = Fixtures.image(width: 8, height: 8) { x, y in (x == 7 && y == 7) ? 255 : 0 }
        let small = image.resized(width: 2, height: 2)
        XCTAssertEqual(small.pixels[0], 0)
        XCTAssertGreaterThan(small.pixels[3], 0)
    }

    func testUpscaleProducesRequestedDimensions() {
        let small = Fixtures.scene(width: 8, height: 8)
        let big = small.resized(width: 20, height: 12)
        XCTAssertEqual(big.width, 20)
        XCTAssertEqual(big.height, 12)
        XCTAssertEqual(big.pixels.count, 240)
    }

    func testInitRejectsMismatchedBufferLength() {
        XCTAssertNil(GrayImage(width: 3, height: 3, pixels: [0, 1, 2]))
        XCTAssertNil(GrayImage(width: 0, height: 3, pixels: []))
    }
}

final class PerceptualHasherTests: XCTestCase {

    func testHashesAreDeterministic() {
        let image = Fixtures.scene()
        XCTAssertEqual(PerceptualHasher.dHash(image), PerceptualHasher.dHash(image))
        XCTAssertEqual(PerceptualHasher.pHash(image), PerceptualHasher.pHash(image))
    }

    func testRescalingBarelyMovesTheHash() {
        // The common case: the same photo saved at a smaller size by a messaging app.
        let original = Fixtures.scene(width: 256, height: 256)
        let rescaled = original.resized(width: 96, height: 96)

        let pDistance = hammingDistance(PerceptualHasher.pHash(original), PerceptualHasher.pHash(rescaled))
        let dDistance = hammingDistance(PerceptualHasher.dHash(original), PerceptualHasher.dHash(rescaled))

        XCTAssertLessThanOrEqual(pDistance, 8, "pHash drifted \(pDistance) bits on a pure rescale")
        XCTAssertLessThanOrEqual(dDistance, 12, "dHash drifted \(dDistance) bits on a pure rescale")
    }

    func testBrightnessShiftBarelyMovesDHash() {
        // Deliberately built so +25 does not clip: clipping is a different effect and would
        // make this test about saturation rather than about exposure.
        let original = Fixtures.image(width: 128, height: 128) { x, y in
            40 + (x * 90 / 127) + (y * 60 / 127)
        }
        let brighter = Fixtures.image(width: 128, height: 128) { x, y in
            Int(original.pixel(x: x, y: y)) + 25
        }
        let distance = hammingDistance(PerceptualHasher.dHash(original), PerceptualHasher.dHash(brighter))
        XCTAssertLessThanOrEqual(distance, 4, "dHash drifted \(distance) bits on a uniform exposure shift")
    }

    func testDifferentScenesAreFarApart() {
        let gradient = Fixtures.scene(width: 128, height: 128)

        var rng = SplitMix64(seed: 1234)
        var noise = [UInt8](repeating: 0, count: 128 * 128)
        for index in 0..<noise.count {
            noise[index] = UInt8.random(in: 0...255, using: &rng)
        }
        let random = GrayImage(width: 128, height: 128, pixels: noise)!

        let pDistance = hammingDistance(PerceptualHasher.pHash(gradient), PerceptualHasher.pHash(random))
        let dDistance = hammingDistance(PerceptualHasher.dHash(gradient), PerceptualHasher.dHash(random))

        XCTAssertGreaterThan(pDistance, 16, "unrelated images collapsed to \(pDistance) bits apart")
        XCTAssertGreaterThan(dDistance, 16, "unrelated images collapsed to \(dDistance) bits apart")
    }

    func testFlatImageStillProducesAHash() {
        let flat = Fixtures.image(width: 64, height: 64) { _, _ in 128 }
        XCTAssertEqual(PerceptualHasher.dHash(flat), 0)
        _ = PerceptualHasher.pHash(flat)
    }
}

final class HammingTests: XCTestCase {

    func testKnownDistances() {
        XCTAssertEqual(hammingDistance(0, 0), 0)
        XCTAssertEqual(hammingDistance(0, UInt64.max), 64)
        XCTAssertEqual(hammingDistance(0b1011, 0b1110), 2)
    }

    func testSymmetryAndTriangleInequality() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<500 {
            let a = UInt64.random(in: .min ... .max, using: &rng)
            let b = UInt64.random(in: .min ... .max, using: &rng)
            let c = UInt64.random(in: .min ... .max, using: &rng)
            XCTAssertEqual(hammingDistance(a, b), hammingDistance(b, a))
            XCTAssertLessThanOrEqual(hammingDistance(a, c), hammingDistance(a, b) + hammingDistance(b, c))
        }
    }
}
