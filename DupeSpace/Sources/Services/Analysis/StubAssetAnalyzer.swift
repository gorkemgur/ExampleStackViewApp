import Foundation
import DupeCore

/// Analyzer for UI tests and previews.
///
/// The fixtures are shaped so the results screen has something of every kind to show: a pair
/// of byte-identical 1.8 GB videos, a messaging-app re-encode next to its original, and a
/// burst whose frames are close enough to see but far enough apart that the engine refuses to
/// call them the same shot.
final class StubAssetAnalyzer: AssetAnalyzing {

    let digests: [String: ContentDigestResult]
    let hashes: [String: PerceptualHashes]
    let prints: [String: FeaturePrint]
    let signatures: [String: VideoSignature]
    private let stepDelay: Duration

    init(
        digests: [String: ContentDigestResult],
        hashes: [String: PerceptualHashes],
        prints: [String: FeaturePrint] = [:],
        signatures: [String: VideoSignature] = [:],
        stepDelay: Duration = .zero
    ) {
        self.digests = digests
        self.hashes = hashes
        self.prints = prints
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

    /// Both fingerprints, the way a Vision-backed analyzer produces them.
    ///
    /// The fixtures carry prints because the matcher prefers them: without one here, every UI
    /// test would exercise the fallback and the branch the app actually runs on a phone would
    /// never be executed by anything.
    func imageFingerprint(for item: MediaItem) async -> ImageFingerprint? {
        if stepDelay > .zero { try? await Task.sleep(for: stepDelay) }
        guard let hashes = hashes[item.id] else { return nil }
        return ImageFingerprint(hashes: hashes, featurePrint: prints[item.id])
    }

    func videoSignature(for item: MediaItem) async -> VideoSignature? {
        if stepDelay > .zero { try? await Task.sleep(for: stepDelay) }
        return signatures[item.id]
    }

    // MARK: - Fixture

    static func uiTestFixture(stepDelay: Duration = .zero) -> StubAssetAnalyzer {
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

        // The same relationships the hashes above describe, said in the units Vision speaks.
        // Each scene owns a plane nothing else uses, so two items from different scenes are
        // orthogonal — a distance of 2.0, far outside anything the matcher opens.
        var prints: [String: FeaturePrint] = [
            "photo-cliff": print(scene: 1),
            // 0.0031 is the measured distance between a photograph and a 1280 px downscale of
            // it, which is exactly what this pair is.
            "photo-cliff-resend": print(scene: 1, apart: 0.0031)
        ]
        for index in 0..<6 {
            // Neighbouring frames a tenth apart: past "the same shot", inside "worth showing
            // you". Frames two apart come out at 0.39 and are not offered as a pair, which is
            // what the seven-bit spacing above does too.
            prints["burst-\(index)"] = print(scene: 2, turns: index, apart: 0.10)
        }
        for index in 0..<14 {
            prints["screenshot-\(index)"] = print(scene: 10 + index)
        }

        return StubAssetAnalyzer(
            digests: [
                "video-holiday": .digest(sharedVideoDigest),
                "video-holiday-copy": .digest(sharedVideoDigest)
            ],
            hashes: hashes,
            prints: prints,
            signatures: signatures,
            stepDelay: stepDelay
        )
    }

    /// The UI-test fixture with twelve more pairs of similar photographs in it.
    ///
    /// Each pair is seven bits apart — the same distance the burst uses, which the engine reads
    /// as "the same shot, worth showing you" and refuses to pre-tick — but with no burst
    /// identifier on the items, so `RegretTier` files them under similar shots rather than burst
    /// leftovers. Every pair's base is scrambled from its index, so no pair is within reach of
    /// another and the rung holds twelve groups rather than one large one.
    static func crowdedFixture(stepDelay: Duration = .zero) -> StubAssetAnalyzer {
        let base = uiTestFixture(stepDelay: stepDelay)
        var hashes = base.hashes
        var prints = base.prints

        for index in 0..<12 {
            let seed = scramble(UInt64(index) &+ 0x5EED_0C12_3456_789A)
            // The last pair is a crop, and a crop is the case this app could not see until it
            // had feature prints: 34 bits of 64 is what a 30 % crop scores, and it is also what
            // a photograph of something else scores. If the print ever stops reaching the
            // matcher, eleven of these twelve pairs survive on their hashes and this one
            // vanishes — which is the point of it being here.
            let bitsApart = index == croppedPairIndex ? 34 : 7
            hashes["crowd-\(index)-a"] = PerceptualHashes(dHash: seed, pHash: scramble(seed))
            hashes["crowd-\(index)-b"] = PerceptualHashes(
                dHash: flipping(seed, bits: bitsApart),
                pHash: flipping(scramble(seed), bits: bitsApart)
            )

            prints["crowd-\(index)-a"] = print(scene: 30 + index)
            prints["crowd-\(index)-b"] = print(
                scene: 30 + index,
                apart: index == croppedPairIndex ? 0.1036 : 0.10
            )
        }

        return StubAssetAnalyzer(
            digests: base.digests,
            hashes: hashes,
            prints: prints,
            signatures: base.signatures,
            stepDelay: stepDelay
        )
    }

    /// Which of the crowded fixture's twelve pairs the hashes cannot see.
    static let croppedPairIndex = 11

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
        var prints: [String: FeaturePrint] = [:]
        var signatures: [String: VideoSignature] = [:]

        for (offset, item) in StubMediaLibrary.sampleItems().enumerated() {
            let seed = scramble(UInt64(bitPattern: Int64(item.id.hashValue)))
            digests[item.id] = .digest(
                ContentDigest(bytes: (0..<32).map { UInt8(truncatingIfNeeded: seed &>> UInt64($0 % 8 * 8) &+ UInt64($0)) })
            )
            hashes[item.id] = PerceptualHashes(dHash: seed, pHash: scramble(seed))
            // A plane per item, so every pair is orthogonal and the tidy library stays tidy
            // under the print as well as under the hashes.
            prints[item.id] = print(scene: offset)
            if item.kind == .video {
                signatures[item.id] = VideoSignature(
                    frameHashes: (0..<10).map { scramble(seed &+ UInt64($0)) }
                )
            }
        }

        return StubAssetAnalyzer(digests: digests, hashes: hashes, prints: prints, signatures: signatures)
    }

    /// A synthetic feature print.
    ///
    /// Two axes per scene and nothing shared between scenes, so items from different scenes sit
    /// at 2.0 — orthogonal, and nowhere near any threshold. Within a scene the variant is
    /// rotated by exactly the angle that produces `apart`, because the fixture should say the
    /// measured number it stands for rather than an arbitrary one. `turns` walks a burst around
    /// the same arc a step at a time.
    private static func print(scene: Int, turns: Int = 1, apart distance: Double = 0) -> FeaturePrint {
        var elements = [Float](repeating: 0, count: 768)
        let step = acos(max(-1, min(1, 1 - distance / 2)))
        let angle = step * Double(turns)
        elements[(scene * 2) % 768] = Float(cos(angle))
        elements[(scene * 2 + 1) % 768] = Float(sin(angle))
        return FeaturePrint(descriptor: "stub.fp1", elements: elements)
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
