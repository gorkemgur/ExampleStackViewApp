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
    private let signatures: [String: VideoSignature]
    private let stepDelay: Duration

    init(
        digests: [String: ContentDigestResult],
        hashes: [String: PerceptualHashes],
        signatures: [String: VideoSignature] = [:],
        stepDelay: Duration = .zero
    ) {
        self.digests = digests
        self.hashes = hashes
        self.signatures = signatures
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

    func videoSignature(for item: MediaItem) async -> VideoSignature? {
        if stepDelay > .zero { try? await Task.sleep(for: stepDelay) }
        return signatures[item.id]
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

        // The same trip, once at full size and once as it came back from a chat. Nothing in
        // the metadata says they are the same; only the frames do.
        let tripFrames: [UInt64] = [0x2F, 0x51, 0x8C, 0xB3, 0x17, 0x6A, 0xD4, 0x39, 0xE2, 0x7B]
        let signatures: [String: VideoSignature] = [
            "video-trip": VideoSignature(frameHashes: tripFrames),
            "video-trip-sent": VideoSignature(frameHashes: tripFrames.map { $0 ^ 0b11 })
        ]

        return StubAssetAnalyzer(
            digests: [
                "video-holiday": .digest(sharedVideoDigest),
                "video-holiday-copy": .digest(sharedVideoDigest)
            ],
            hashes: hashes,
            signatures: signatures
        )
    }

    /// The same library with nothing in it that matches anything.
    ///
    /// A tidy library is the state this app is least often looked at in, and it is the one a
    /// first-time user is most likely to be in: the scan does all of its real work — buckets
    /// on metadata, opens every photograph, samples the two videos whose lengths agree — and
    /// then honestly finds nothing. The storage figures on the overview stay real, so the
    /// screens are the ones people see rather than a blanked-out shell.
    ///
    /// Every value is derived from the item's own id, so nothing collides and the fixture is
    /// the same on every run.
    static func cleanFixture() -> StubAssetAnalyzer {
        var digests: [String: ContentDigestResult] = [:]
        var hashes: [String: PerceptualHashes] = [:]
        var signatures: [String: VideoSignature] = [:]

        for item in StubMediaLibrary.sampleItems() {
            let seed = scramble(UInt64(bitPattern: Int64(item.id.hashValue)))
            digests[item.id] = .digest(
                ContentDigest(bytes: (0..<32).map { UInt8(truncatingIfNeeded: seed &>> UInt64($0 % 8 * 8) &+ UInt64($0)) })
            )
            hashes[item.id] = PerceptualHashes(dHash: seed, pHash: scramble(seed))
            if item.kind == .video {
                signatures[item.id] = VideoSignature(
                    frameHashes: (0..<10).map { scramble(seed &+ UInt64($0)) }
                )
            }
        }

        return StubAssetAnalyzer(digests: digests, hashes: hashes, signatures: signatures)
    }

    /// SplitMix64's finalising mix. `hashValue` is seeded per process, so two ids can land
    /// close together; this spreads them far enough apart that no pair is ever within a
    /// perceptual distance of each other.
    private static func scramble(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }

    private static func flipping(_ value: UInt64, bits: Int) -> UInt64 {
        var result = value
        for bit in 0..<bits { result ^= (UInt64(1) << UInt64(bit)) }
        return result
    }
}
