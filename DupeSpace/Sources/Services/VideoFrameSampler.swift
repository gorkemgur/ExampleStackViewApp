import AVFoundation
import CoreGraphics
import DupeCore

/// Turns a video into the handful of frame fingerprints the matcher compares.
enum VideoFrameSampler {

    /// Frames are pulled at fixed relative positions so two recordings of the same footage
    /// line up regardless of how long they are.
    ///
    /// Returns `nil` if any single sample fails. A signature with a gap in it would be
    /// compared against another video's frames one position out, which is a worse answer than
    /// no answer.
    static func signature(for asset: AVAsset) async -> VideoSignature? {
        guard
            let duration = try? await asset.load(.duration)
        else {
            return nil
        }

        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)

        // Snapping to a nearby keyframe instead of decoding to an exact timestamp is the
        // difference between a scan that finishes and one that does not. The matcher already
        // tolerates a frame of drift.
        let tolerance = CMTime(seconds: 0.4, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var frames: [UInt64] = []
        frames.reserveCapacity(VideoSignature.samplePositions.count)

        for position in VideoSignature.samplePositions {
            let time = CMTime(seconds: seconds * position, preferredTimescale: 600)
            guard
                let result = try? await generator.image(at: time),
                let gray = GrayImageRenderer.render(result.image)
            else {
                return nil
            }
            frames.append(PerceptualHasher.pHash(gray))
        }

        return VideoSignature(frameHashes: frames)
    }
}
