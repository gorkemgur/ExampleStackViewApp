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

    /// Fingerprints of frames sampled across a video. `nil` when the video cannot be read
    /// locally, or when any sample failed — a signature with a gap in it would line up
    /// against another video's frames wrongly, which is worse than having none.
    func videoSignature(for item: MediaItem) async -> VideoSignature?
}

public extension AssetAnalyzing {

    /// Sources that hold no video, and callers that only care about stills, get this for free.
    func videoSignature(for item: MediaItem) async -> VideoSignature? { nil }
}
