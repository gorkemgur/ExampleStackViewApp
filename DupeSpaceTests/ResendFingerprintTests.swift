import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import DupeCore
@testable import DupeSpace

/// Does the picture the fixture library calls a re-send actually fingerprint like one?
///
/// The real-library CI job put twelve photographs into a simulator's Photos library — two
/// pairs sharing every byte, two pairs where the second copy is the same picture at half the
/// size and a third of the quality — and found the byte-identical pairs and neither re-send.
/// Three things could produce that, and they have three different fixes: PhotoKit could be
/// handing the analyzer a thumbnail that does not survive the size change, the scan could be
/// setting the pair aside before it compares them, or the fingerprints of those two particular
/// pictures could genuinely be further apart than the matcher's threshold.
///
/// The third is the one that needs no photo library to settle, so it goes first. This builds
/// the same two files `Scripts/make-library.swift` builds — same seed, same scene, same sizes,
/// same JPEG qualities, written to disk and read back so the compression is real — and puts
/// them through the same renderer and the same two hashers the app uses. If the distances come
/// back inside the threshold, the fixture is sound and the fault is above it. If they do not,
/// the fault was in what I asked the app to find.
///
/// The scene drawing is a copy of the script's, deliberately: the script is run by `swift` as
/// a standalone file and cannot be imported. The seed and the constants are what must match,
/// and a drift in them shows up here as a distance that no longer means anything about the
/// fixture — which is why the control case at the bottom asserts two *different* scenes stay
/// far apart.
final class ResendFingerprintTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("resend-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    // MARK: - The fixture, rebuilt

    /// SplitMix64, so a scene is a function of its number and nothing else.
    private struct Seeded {
        private var state: UInt64
        init(_ seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }

    private func draw(scene: Int, width: Int, height: Int) throws -> CGImage {
        var random = Seeded(UInt64(scene) &* 0x9E37_79B9)
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))

        let base = (r: random.unit(), g: random.unit(), b: random.unit())
        context.setFillColor(red: base.r * 0.5, green: base.g * 0.5, blue: base.b * 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let wash = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(red: base.r, green: base.g, blue: base.b, alpha: 1),
                CGColor(red: base.b * 0.3, green: base.r * 0.3, blue: base.g * 0.3, alpha: 1)
            ] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                wash, start: .zero, end: CGPoint(x: width, y: height), options: []
            )
        }

        for _ in 0..<7 {
            let radius = Double(min(width, height)) * (0.08 + random.unit() * 0.22)
            let x = random.unit() * Double(width)
            let y = random.unit() * Double(height)
            context.setFillColor(red: random.unit(), green: random.unit(), blue: random.unit(), alpha: 0.55)
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }

        return try XCTUnwrap(context.makeImage())
    }

    private func scaled(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// Write a JPEG and read it back, so the compression is in the pixels being hashed rather
    /// than assumed away.
    private func roundTripped(_ image: CGImage, quality: Double, named name: String) throws -> CGImage {
        let url = root.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "could not write \(name)")

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func fingerprint(_ image: CGImage) throws -> PerceptualHashes {
        let gray = try XCTUnwrap(GrayImageRenderer.render(image))
        return PerceptualHashes(dHash: PerceptualHasher.dHash(gray), pHash: PerceptualHasher.pHash(gray))
    }

    /// The pair as the fixture writes it: 2400x1800 at quality 0.95, and 1200x900 at 0.45.
    private func resendPair(scene: Int) throws -> (full: PerceptualHashes, resend: PerceptualHashes) {
        let full = try draw(scene: scene, width: 2400, height: 1800)
        let small = try scaled(full, width: 1200, height: 900)
        return (
            try fingerprint(roundTripped(full, quality: 0.95, named: "photo-\(scene).jpg")),
            try fingerprint(roundTripped(small, quality: 0.45, named: "photo-\(scene)-resend.jpg"))
        )
    }

    // MARK: - The question

    private func assertMatches(scene: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let pair = try resendPair(scene: scene)
        let limit = ScanStrictness.balanced.configuration.similarDistance
        let d = hammingDistance(pair.full.dHash, pair.resend.dHash)
        let p = hammingDistance(pair.full.pHash, pair.resend.pHash)

        // Both, because the matcher requires both: dHash proposes and pHash gets a veto.
        XCTAssertLessThanOrEqual(
            d, limit,
            "scene \(scene): dHash is \(d) bits apart, and a balanced scan matches at \(limit) or fewer",
            file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            p, limit,
            "scene \(scene): pHash is \(p) bits apart, and a balanced scan matches at \(limit) or fewer",
            file: file, line: line
        )
    }

    func testTheFixturesFirstResendPairFingerprintsAsAMatch() throws {
        try assertMatches(scene: 3)
    }

    func testTheFixturesSecondResendPairFingerprintsAsAMatch() throws {
        try assertMatches(scene: 4)
    }

    /// The half that catches a threshold made loose enough to pass the half above.
    func testTwoDifferentFixtureScenesStayFarApart() throws {
        let one = try fingerprint(roundTripped(draw(scene: 3, width: 2400, height: 1800), quality: 0.95, named: "a.jpg"))
        let two = try fingerprint(roundTripped(draw(scene: 5, width: 2400, height: 1800), quality: 0.95, named: "b.jpg"))
        let limit = ScanStrictness.loose.configuration.similarDistance

        let d = hammingDistance(one.dHash, two.dHash)
        let p = hammingDistance(one.pHash, two.pHash)
        XCTAssertTrue(
            d > limit || p > limit,
            "two unrelated scenes came back \(d)/\(p) bits apart, inside even a loose scan's \(limit)"
        )
    }

    /// The step the tests above skip, and the only thing left between them and the real path.
    ///
    /// `ResendFingerprintTests` above draws the fingerprint from the full-size picture. The app
    /// never sees a full-size picture: `PhotoKitAssetAnalyzer` asks `PHImageManager` for the
    /// asset at `GrayImageRenderer.renderSize` — 64 points — and hashes whatever comes back. So
    /// there are two resamplings in the real path and one in the test, and the first of them
    /// throws away everything the second would have had to work with.
    ///
    /// That matters most for dHash, which compares neighbouring pixels. At sixty-four pixels
    /// across, a 2400-wide original and a 1200-wide copy have been through different amounts of
    /// decimation and carry different aliasing, and on a smooth picture the neighbour
    /// differences the hash is reading are the same size as that noise.
    ///
    /// So: the same pair, through the same two stages the app puts it through, at the size the
    /// app asks for — and the distance at the larger sizes printed beside it, because if this
    /// fails the next question is immediately "how much larger does the request have to be".
    func testThePairStillMatchesAfterTheThumbnailStepTheAppActuallyTakes() throws {
        let full = try draw(scene: 3, width: 2400, height: 1800)
        let small = try scaled(full, width: 1200, height: 900)
        let one = try roundTripped(full, quality: 0.95, named: "thumb-full.jpg")
        let two = try roundTripped(small, quality: 0.45, named: "thumb-resend.jpg")
        let limit = ScanStrictness.balanced.configuration.similarDistance

        /// What `PHImageManager` returns for a square target and `contentMode: .aspectFit`:
        /// the picture scaled to fit inside that box, so a 4:3 photograph comes back
        /// `side` by `side * 3 / 4`.
        func throughAThumbnail(_ image: CGImage, side: Int) throws -> PerceptualHashes {
            try fingerprint(scaled(image, width: side, height: side * 3 / 4))
        }

        var measured: [String] = []
        for side in [64, 128, 256, 512] {
            let a = try throughAThumbnail(one, side: side)
            let b = try throughAThumbnail(two, side: side)
            measured.append(
                "\(side)pt: dHash \(hammingDistance(a.dHash, b.dHash)), pHash \(hammingDistance(a.pHash, b.pHash))"
            )
        }
        let evidence = measured.joined(separator: "   ")

        let asked = try throughAThumbnail(one, side: GrayImageRenderer.renderSize)
        let gets = try throughAThumbnail(two, side: GrayImageRenderer.renderSize)
        let d = hammingDistance(asked.dHash, gets.dHash)
        let p = hammingDistance(asked.pHash, gets.pHash)

        XCTAssertLessThanOrEqual(
            max(d, p), limit,
            "at the \(GrayImageRenderer.renderSize)pt the analyzer asks for, the pair is "
            + "\(d)/\(p) bits apart and a balanced scan matches at \(limit).   \(evidence)"
        )
    }

    /// Scale alone, with no quality loss, to separate the two halves of what a re-send does.
    ///
    /// If this passes and the pair above fails, the size change is survivable and the JPEG
    /// quality is what breaks the fingerprint; if this fails too, the renderer does not
    /// survive being handed the same picture at two sizes, which is a far larger problem —
    /// every match in this app rests on it.
    func testHalvingTheSizeAloneDoesNotMoveTheFingerprint() throws {
        let full = try draw(scene: 3, width: 2400, height: 1800)
        let small = try scaled(full, width: 1200, height: 900)
        let one = try fingerprint(full)
        let two = try fingerprint(small)
        let limit = ScanStrictness.balanced.configuration.nearExactDistance

        XCTAssertLessThanOrEqual(
            hammingDistance(one.dHash, two.dHash), limit,
            "dHash moved \(hammingDistance(one.dHash, two.dHash)) bits on a resize alone"
        )
        XCTAssertLessThanOrEqual(
            hammingDistance(one.pHash, two.pHash), limit,
            "pHash moved \(hammingDistance(one.pHash, two.pHash)) bits on a resize alone"
        )
    }
}
