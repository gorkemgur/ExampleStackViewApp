import Foundation
import DupeCore

/// Analyzer for UI tests and previews.
///
/// The fixtures are shaped so the results screen has something of every kind to show: a pair
/// of byte-identical 1.8 GB videos, a messaging-app re-encode next to its original, and a
/// burst whose frames are close enough to see but far enough apart that the engine refuses to
/// call them the same shot.
final class StubAssetAnalyzer: AssetAnalyzing {

    private let digests: [String: ContentDigestResult]
    private let hashes: [String: PerceptualHashes]
    private let stepDelay: Duration

    init(
        digests: [String: ContentDigestResult],
        hashes: [String: PerceptualHashes],
        stepDelay: Duration = .zero
    ) {
        self.digests = digests
        self.hashes = hashes
        self.stepDelay = stepDelay
    }

    func contentDigest(for item: MediaItem) async -> ContentDigestResult {
        if stepDelay > .zero { try? await Task.sleep(for: stepDelay) }
        return digests[item.id] ?? .unavailable
    }

    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
        if stepDelay > .zero { try? await Task.sleep(for: stepDelay) }
        return hashes[item.id]
    }

    // MARK: - Fixture

    static func uiTestFixture() -> StubAssetAnalyzer {
        let sharedVideoDigest = ContentDigest(bytes: [UInt8](repeating: 0xA7, count: 32))

        let baseD: UInt64 = 0x0F1E_2D3C_4B5A_6978
        let baseP: UInt64 = 0xA1B2_C3D4_E5F6_0718

        var hashes: [String: PerceptualHashes] = [
            // The original and the copy that came back from a chat, four bits apart.
            "photo-cliff": PerceptualHashes(dHash: baseD, pHash: baseP),
            "photo-cliff-resend": PerceptualHashes(
                dHash: flipping(baseD, bits: 4),
                pHash: flipping(baseP, bits: 4)
            )
        ]

        // A burst. Seven bits between neighbouring frames: past the threshold for "the same
        // shot", inside the one for "worth showing you", which is exactly where a burst
        // belongs — the engine refuses to pre-tick any of it.
        let burstD: UInt64 = 0x3344_5566_7788_99AA
        let burstP: UInt64 = 0xCAFE_BABE_1234_5678
        for index in 0..<6 {
            hashes["burst-\(index)"] = PerceptualHashes(
                dHash: flipping(burstD, bits: index * 7),
                pHash: flipping(burstP, bits: index * 7)
            )
        }

        // Screenshots of different things: nothing should match.
        for index in 0..<14 {
            hashes["screenshot-\(index)"] = PerceptualHashes(
                dHash: UInt64(index) &* 0x9E37_79B9_7F4A_7C15,
                pHash: UInt64(index) &* 0xBF58_476D_1CE4_E5B9
            )
        }

        return StubAssetAnalyzer(
            digests: [
                "video-holiday": .digest(sharedVideoDigest),
                "video-holiday-copy": .digest(sharedVideoDigest)
            ],
            hashes: hashes
        )
    }

    private static func flipping(_ value: UInt64, bits: Int) -> UInt64 {
        var result = value
        for bit in 0..<bits { result ^= (UInt64(1) << UInt64(bit)) }
        return result
    }
}
