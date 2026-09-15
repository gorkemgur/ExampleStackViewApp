import XCTest
@testable import DupeCore

/// What happens when the engine has a feature print for both sides of a pair.
///
/// The measurement this exists for is in `docs/OPPORTUNITIES.md` §9.1: a 30 % crop scores 34 of
/// 64 against dHash/pHash, which is bit for bit what a completely unrelated photograph scores.
/// No threshold separates those, so the bottom of the ladder was never going to work on hashes
/// alone. Everything here is about the pair the hashes cannot judge, and about not breaking the
/// pairs they can.
final class FeaturePrintMatchingTests: XCTestCase {

    /// An analyzer that answers with feature prints as well as hashes, the way a Vision-backed
    /// one does. Tests that want the old world simply do not give it any prints.
    private final class PrintingAnalyzer: AssetAnalyzing, @unchecked Sendable {

        private let hashes: [String: PerceptualHashes]
        private let prints: [String: FeaturePrint]

        init(hashes: [String: PerceptualHashes], prints: [String: FeaturePrint] = [:]) {
            self.hashes = hashes
            self.prints = prints
        }

        func contentDigest(for item: MediaItem) async -> ContentDigestResult { .unavailable }

        func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? { hashes[item.id] }

        func imageFingerprint(for item: MediaItem) async -> ImageFingerprint? {
            guard let hashes = hashes[item.id] else { return nil }
            return ImageFingerprint(hashes: hashes, featurePrint: prints[item.id])
        }
    }

    // MARK: - Vectors at the measured distances

    /// A unit vector, then the same vector tilted until it sits `distance` away in the squared
    /// Euclidean the engine uses. Lets a test say "these two are a 30 % crop apart" and mean the
    /// number that was actually measured rather than an invented one.
    private func pair(apart distance: Double, revision: String = "vision.revision2") -> (FeaturePrint, FeaturePrint) {
        // For unit vectors, squared distance d gives cos θ = 1 − d/2.
        let cosine = 1 - distance / 2
        let sine = (1 - cosine * cosine).squareRoot()
        var first = [Float](repeating: 0, count: 768)
        var second = [Float](repeating: 0, count: 768)
        first[0] = 1
        second[0] = Float(cosine)
        second[1] = Float(sine)
        return (
            FeaturePrint(descriptor: revision, elements: first),
            FeaturePrint(descriptor: revision, elements: second)
        )
    }

    private func hashes(_ dHash: UInt64, _ pHash: UInt64) -> PerceptualHashes {
        PerceptualHashes(dHash: dHash, pHash: pHash)
    }

    private func flipping(_ value: UInt64, bits: Int) -> UInt64 {
        var result = value
        for bit in 0..<bits { result ^= (UInt64(1) << UInt64(bit)) }
        return result
    }

    private let baseD: UInt64 = 0x0F1E_2D3C_4B5A_6978
    private let baseP: UInt64 = 0xA1B2_C3D4_E5F6_0718

    private func items() -> [MediaItem] {
        [
            Fixtures.item("original", bytes: 2_000_000, width: 4032, height: 3024),
            Fixtures.item("crop", bytes: 1_400_000, width: 4032, height: 3024)
        ]
    }

    // MARK: - The pair the hashes cannot judge

    func testACropTheHashesCallUnrelatedIsStillFoundByItsPrint() async throws {
        // 34 bits apart: the measured score of a 30 % crop, and also the measured score of a
        // photograph of something else entirely.
        let analyzer = PrintingAnalyzer(
            hashes: [
                "original": hashes(baseD, baseP),
                "crop": hashes(flipping(baseD, bits: 34), flipping(baseP, bits: 34))
            ],
            prints: {
                let (a, b) = pair(apart: 0.1036)
                return ["original": a, "crop": b]
            }()
        )

        let result = try await ScanPipeline(analyzer: analyzer).run(items: items())

        XCTAssertEqual(result.groups.count, 1, "the print says 0.1036, which is a crop of the same photograph")
        XCTAssertEqual(result.groups.first?.relation, .similar)
    }

    func testTwoPhotographsTheHashesLikeAreRefusedWhenTheirPrintsDisagree() async throws {
        // Two bits apart is well inside `nearExactDistance`, so on hashes alone this pair would
        // be offered as the same shot — and pre-ticked.
        let analyzer = PrintingAnalyzer(
            hashes: [
                "original": hashes(baseD, baseP),
                "crop": hashes(flipping(baseD, bits: 2), flipping(baseP, bits: 2))
            ],
            prints: {
                let (a, b) = pair(apart: 1.6697)
                return ["original": a, "crop": b]
            }()
        )

        let result = try await ScanPipeline(analyzer: analyzer).run(items: items())

        XCTAssertTrue(
            result.groups.isEmpty,
            "1.6697 is the measured distance between two different photographs; a hash collision must not outvote that"
        )
    }

    func testThePrintDecidesTheTierAndNotOnlyTheMatch() async throws {
        let analyzer = PrintingAnalyzer(
            hashes: [
                "original": hashes(baseD, baseP),
                "crop": hashes(flipping(baseD, bits: 34), flipping(baseP, bits: 34))
            ],
            prints: {
                // 0.0013: the measured distance between a photograph and a q40 re-encode of it.
                let (a, b) = pair(apart: 0.0013)
                return ["original": a, "crop": b]
            }()
        )

        let result = try await ScanPipeline(analyzer: analyzer).run(items: items())

        XCTAssertEqual(result.groups.first?.relation, .nearExact, "a re-encode is the same shot, whatever the hashes made of it")
    }

    // MARK: - Not breaking the pairs the hashes can judge

    func testAPairWithNoPrintsIsJudgedExactlyAsItWasBefore() async throws {
        let analyzer = PrintingAnalyzer(
            hashes: [
                "original": hashes(baseD, baseP),
                "crop": hashes(flipping(baseD, bits: 4), flipping(baseP, bits: 4))
            ]
        )

        let result = try await ScanPipeline(analyzer: analyzer).run(items: items())

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups.first?.relation, .nearExact)
    }

    func testOneSidedPrintsFallBackToTheHashes() async throws {
        let analyzer = PrintingAnalyzer(
            hashes: [
                "original": hashes(baseD, baseP),
                "crop": hashes(flipping(baseD, bits: 4), flipping(baseP, bits: 4))
            ],
            prints: ["original": pair(apart: 0.1).0]
        )

        let result = try await ScanPipeline(analyzer: analyzer).run(items: items())

        XCTAssertEqual(
            result.groups.count,
            1,
            "one print is not a comparison; the pair still has two hashes that agree and must be judged on those"
        )
    }

    func testPrintsFromTwoRevisionsFallBackRatherThanRefuse() async throws {
        let analyzer = PrintingAnalyzer(
            hashes: [
                "original": hashes(baseD, baseP),
                "crop": hashes(flipping(baseD, bits: 4), flipping(baseP, bits: 4))
            ],
            prints: [
                "original": pair(apart: 0).0,
                "crop": pair(apart: 0, revision: "vision.revision1").0
            ]
        )

        let result = try await ScanPipeline(analyzer: analyzer).run(items: items())

        XCTAssertEqual(
            result.groups.count,
            1,
            "two revisions cannot be compared, and 'cannot say' has to fall back to what can — not silently veto a pair the hashes agree on"
        )
    }

    // MARK: - The seam itself

    func testAnAnalyzerThatOnlyKnowsHashesStillWorks() async throws {
        // Every analyzer in this codebase except the two Vision-backed ones implements
        // `perceptualHashes` and nothing else. The default has to keep them whole.
        final class OldAnalyzer: AssetAnalyzing, @unchecked Sendable {
            func contentDigest(for item: MediaItem) async -> ContentDigestResult { .unavailable }
            func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
                PerceptualHashes(dHash: 0x0F1E_2D3C_4B5A_6978, pHash: 0xA1B2_C3D4_E5F6_0718)
            }
        }

        let fingerprint = await OldAnalyzer().imageFingerprint(for: Fixtures.item("a"))

        XCTAssertEqual(fingerprint?.hashes.dHash, 0x0F1E_2D3C_4B5A_6978)
        XCTAssertNil(fingerprint?.featurePrint, "no Vision behind it means no print, not an empty one")
    }
}
