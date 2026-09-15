import Foundation

/// The two 64-bit fingerprints computed for one image.
public struct PerceptualHashes: Sendable, Hashable, Codable {

    public let dHash: UInt64
    public let pHash: UInt64

    public init(dHash: UInt64, pHash: UInt64) {
        self.dHash = dHash
        self.pHash = pHash
    }
}

/// Everything one decode of an image produces.
///
/// The two fingerprints answer different questions and cost almost nothing together: at 224 px
/// the feature print is 26.9 ms against dHash+pHash's 14.9 ms at 64 px, and both figures are
/// dominated by the same JPEG decode — the *marginal* cost of the print is about 12 ms
/// (`docs/OPPORTUNITIES.md` §9.7). Returning them as one value is what keeps it that way; two
/// protocol methods would be two decodes, and — worse — two decode *sizes*, which is the one
/// thing measurably capable of changing a feature print distance (0.143 against 0.037 for the
/// same pair at two decode sizes).
public struct ImageFingerprint: Sendable, Hashable {

    public let hashes: PerceptualHashes
    /// `nil` when no Vision-backed analyzer produced one: an older cache entry, a source that
    /// cannot render, or a build that predates this. Absent, not far away.
    public let featurePrint: FeaturePrint?

    public init(hashes: PerceptualHashes, featurePrint: FeaturePrint? = nil) {
        self.hashes = hashes
        self.featurePrint = featurePrint
    }
}

/// Outcome of trying to read an item's original bytes.
public enum ContentDigestResult: Sendable, Hashable {
    case digest(ContentDigest)
    /// The original lives in iCloud. The scan does not download it — that would spend the
    /// user's data allowance without asking — so the item is reported, not hashed.
    case cloudOnly
    /// The read failed for any other reason.
    case unavailable
}

/// Everything the pipeline needs from the platform.
///
/// Split out as a protocol so the pipeline — which decides what gets grouped and therefore
/// what gets offered for deletion — is testable without PhotoKit, Vision or a simulator.
public protocol AssetAnalyzing: Sendable {

    /// Streams the item's original bytes and digests them. Never downloads from iCloud.
    func contentDigest(for item: MediaItem) async -> ContentDigestResult

    /// Renders a small grayscale thumbnail and fingerprints it. `nil` when the item cannot be
    /// rendered locally.
    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes?

    /// Everything one decode yields. An analyzer with Vision behind it overrides this and
    /// produces both from a single decode; everything else inherits the default below.
    func imageFingerprint(for item: MediaItem) async -> ImageFingerprint?

    /// Fingerprints of frames sampled across a video. `nil` when the video cannot be read
    /// locally, or when any sample failed — a signature with a gap in it would line up
    /// against another video's frames wrongly, which is worse than having none.
    func videoSignature(for item: MediaItem) async -> VideoSignature?
}

public extension AssetAnalyzing {

    /// Sources that hold no video, and callers that only care about stills, get this for free.
    func videoSignature(for item: MediaItem) async -> VideoSignature? { nil }

    /// Hashes and no print.
    ///
    /// Every analyzer in this codebase except the Vision-backed ones implements
    /// `perceptualHashes` and nothing else — including every stub and fixture. They keep working
    /// unchanged and keep being judged by the hashes, which is exactly what they were written to
    /// exercise.
    func imageFingerprint(for item: MediaItem) async -> ImageFingerprint? {
        guard let hashes = await perceptualHashes(for: item) else { return nil }
        return ImageFingerprint(hashes: hashes)
    }
}
