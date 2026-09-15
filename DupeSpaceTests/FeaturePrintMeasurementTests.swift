import XCTest
import UIKit
@testable import DupeSpace
import DupeCore

/// The thresholds, measured on this app's own decode path rather than borrowed.
///
/// `docs/OPPORTUNITIES.md` §9.2 has a table of feature print distances — 0.0013 for a q40
/// re-encode, 0.1036 for a 30 % crop, 1.6697 for a different photograph. Every one of those was
/// measured on a Mac, on a corpus of one image, by a probe that did its own decoding. Our
/// thresholds were set from that table, which makes them borrowed numbers about somebody else's
/// pipeline: a different decode size or a different `cropAndScaleOption` moves them, and the
/// second of those moves them by 0.452.
///
/// So this measures the same relationships through `FileAssetAnalyzer.fingerprint(of:)` — the
/// actual production path, at the actual decode size, with the actual crop option — and prints
/// what it found. It asserts the *ordering and the margins* the engine depends on, not the exact
/// values, because the values are a property of a build of Vision and the margins are the thing
/// the app's correctness rests on.
final class FeaturePrintMeasurementTests: XCTestCase {

    // MARK: - A photograph, and things that happen to photographs

    /// Something with real low-frequency structure and real detail, because a flat gradient is
    /// not an image a perceptual model has anything to say about.
    private func photograph(seed: Int, size: Int = 1200) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            let cg = context.cgContext
            let colours = [
                UIColor(hue: CGFloat(seed % 7) / 7, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor,
                UIColor(hue: CGFloat((seed + 3) % 7) / 7, saturation: 0.8, brightness: 0.35, alpha: 1).cgColor
            ] as CFArray
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colours,
                locations: [0, 1]
            )!
            cg.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size, y: size),
                options: []
            )

            var generator = SystemRandomNumberGenerator()
            _ = generator
            var value = UInt64(seed &* 0x9E37_79B9)
            func next() -> Double {
                value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(value >> 33) / Double(UInt64(1) << 31)
            }

            for _ in 0..<40 {
                let radius = 20 + next() * 120
                cg.setFillColor(
                    UIColor(
                        hue: next(),
                        saturation: 0.3 + next() * 0.6,
                        brightness: 0.2 + next() * 0.7,
                        alpha: 1
                    ).cgColor
                )
                cg.fillEllipse(
                    in: CGRect(
                        x: next() * Double(size) - radius,
                        y: next() * Double(size) - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }
        }
        return image.cgImage!
    }

    private func jpeg(_ image: CGImage, quality: CGFloat) -> Data {
        UIImage(cgImage: image).jpegData(compressionQuality: quality)!
    }

    private func scaled(_ image: CGImage, by factor: Double) -> CGImage {
        let size = CGSize(width: Double(image.width) * factor, height: Double(image.height) * factor)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }.cgImage!
    }

    private func cropped(_ image: CGImage, keeping fraction: Double) -> CGImage {
        let inset = (1 - fraction) / 2
        return image.cropping(
            to: CGRect(
                x: Double(image.width) * inset,
                y: Double(image.height) * inset,
                width: Double(image.width) * fraction,
                height: Double(image.height) * fraction
            )
        )!
    }

    /// Every measurement below needs a Vision that works. On a simulator it does not — the GPU
    /// device has no Espresso context and the CPU device returns the same vector for every
    /// image — so these skip rather than fail, and say why. A skipped test is an honest "not
    /// measured here"; a passing one would be a claim nobody checked.
    override func setUpWithError() throws {
        try XCTSkipUnless(
            VisionFeaturePrinter.isUsable,
            "Vision on this platform cannot tell the two probe images apart, so no distance measured here would mean anything. Run this on a device."
        )
    }

    private func fingerprint(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> ImageFingerprint {
        let fingerprint = FileAssetAnalyzer.fingerprint(of: data)
        return try XCTUnwrap(fingerprint, "the production decode path produced no fingerprint at all", file: file, line: line)
    }

    private func hamming(_ a: PerceptualHashes, _ b: PerceptualHashes) -> Int {
        max((a.dHash ^ b.dHash).nonzeroBitCount, (a.pHash ^ b.pHash).nonzeroBitCount)
    }

    // MARK: - Does Vision answer at all here

    func testTheProductionPathProducesAPrintOnThisPlatform() throws {
        let fingerprint = try fingerprint(jpeg(photograph(seed: 1), quality: 0.9))

        let print = try XCTUnwrap(
            fingerprint.featurePrint,
            "Vision returned nothing. Every threshold below is then unreachable and the engine is running on hashes alone"
        )
        XCTAssertEqual(print.descriptor, VisionFeaturePrinter.descriptor)
        XCTAssertEqual(print.elements.count, 768, "revision 2 is 768 elements; 2048 means revision 1 got in")
        XCTAssertEqual(
            print.elements.map { Double($0 * $0) }.reduce(0, +),
            1.0,
            accuracy: 0.01,
            "Vision's vectors are L2-normalised, which is what makes the distance range [0, 4]"
        )
    }

    // MARK: - The measurements the thresholds rest on

    func testEveryVariantOfOnePhotographLandsInsideTheSimilarThreshold() throws {
        let original = photograph(seed: 2)
        let reference = try fingerprint(jpeg(original, quality: 0.9))

        let variants: [(String, Data)] = [
            ("q40 re-encode", jpeg(original, quality: 0.4)),
            ("q15 re-encode", jpeg(original, quality: 0.15)),
            ("half size", jpeg(scaled(original, by: 0.5), quality: 0.9)),
            ("quarter size", jpeg(scaled(original, by: 0.25), quality: 0.9)),
            ("10% crop", jpeg(cropped(original, keeping: 0.9), quality: 0.9)),
            ("30% crop", jpeg(cropped(original, keeping: 0.7), quality: 0.9))
        ]

        let limit = ScanConfiguration.default.featurePrintSimilarDistance
        var worst = 0.0

        for (name, data) in variants {
            let variant = try fingerprint(data)
            let distance = try XCTUnwrap(reference.featurePrint?.distance(to: XCTUnwrap(variant.featurePrint)))
            worst = max(worst, distance)
            Swift.print("MEASURED  \(name): print \(distance), hashes \(hamming(reference.hashes, variant.hashes)) bits")

            XCTAssertLessThan(distance, limit, "\(name) is the same photograph and has to be inside the threshold")
        }

        Swift.print("MEASURED  worst true match: \(worst) against a threshold of \(limit)")
    }

    func testADifferentPhotographIsFurtherAwayThanAnyVariantOfThisOne() throws {
        let original = photograph(seed: 3)
        let reference = try fingerprint(jpeg(original, quality: 0.9))
        let crop = try fingerprint(jpeg(cropped(original, keeping: 0.7), quality: 0.9))
        let other = try fingerprint(jpeg(photograph(seed: 4), quality: 0.9))

        let toCrop = try XCTUnwrap(reference.featurePrint?.distance(to: XCTUnwrap(crop.featurePrint)))
        let toOther = try XCTUnwrap(reference.featurePrint?.distance(to: XCTUnwrap(other.featurePrint)))

        Swift.print("MEASURED  30% crop \(toCrop) · different photograph \(toOther) · margin \(toOther / max(toCrop, 1e-9))x")

        XCTAssertGreaterThan(
            toOther,
            ScanConfiguration.default.featurePrintSimilarDistance,
            "a different photograph must sit outside the threshold, or the engine offers strangers for deletion"
        )
        XCTAssertGreaterThan(toOther, toCrop * 2, "the separation margin is the whole reason this replaced the hashes")
    }

    /// §9.1, re-measured here rather than quoted: the case the hashes cannot judge.
    func testTheHashesCannotSeeACropAndThePrintCan() throws {
        let original = photograph(seed: 5)
        let reference = try fingerprint(jpeg(original, quality: 0.9))
        let crop = try fingerprint(jpeg(cropped(original, keeping: 0.7), quality: 0.9))
        let other = try fingerprint(jpeg(photograph(seed: 6), quality: 0.9))

        let cropBits = hamming(reference.hashes, crop.hashes)
        let otherBits = hamming(reference.hashes, other.hashes)
        let cropDistance = try XCTUnwrap(reference.featurePrint?.distance(to: XCTUnwrap(crop.featurePrint)))

        Swift.print("MEASURED  crop \(cropBits) bits / different \(otherBits) bits / crop print \(cropDistance)")

        XCTAssertGreaterThan(
            cropBits,
            ScanConfiguration.default.similarDistance,
            "if the hashes could see this crop there would be nothing for the print to fix, and this test is the proof they cannot"
        )
        XCTAssertLessThan(cropDistance, ScanConfiguration.default.featurePrintSimilarDistance)
    }

    // MARK: - The contract the descriptor stands for

    func testDecodingTheSamePictureTwiceGivesTheSameVectorExactly() throws {
        let data = jpeg(photograph(seed: 7), quality: 0.9)

        let first = try fingerprint(data)
        let second = try fingerprint(data)

        XCTAssertEqual(
            try first.featurePrint?.distance(to: XCTUnwrap(second.featurePrint)) ?? .nan,
            0,
            accuracy: 1e-12,
            "a cache is only worth having if the same bytes give the same vector"
        )
    }

    func testAPrintSurvivesTheCacheItIsWrittenTo() throws {
        let print = try XCTUnwrap(try fingerprint(jpeg(photograph(seed: 8), quality: 0.9)).featurePrint)

        let restored = FingerprintArchive.records(
            from: FingerprintArchive.data(for: ["a": FingerprintRecord(contentVersion: "v", featurePrint: print)])
        )

        XCTAssertEqual(restored?["a"]?.featurePrint, print)
        XCTAssertEqual(restored?["a"]?.featurePrint?.distance(to: print), 0)
    }
}
