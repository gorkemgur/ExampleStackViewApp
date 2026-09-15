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
        // difference between a scan that finishes and one that does not.
        //
        // But the tolerance has to be measured against the spacing of the samples, not fixed.
        // The ten positions are a tenth of the duration apart, so a flat 0.4s window is wider
        // than *half the gap* for anything under eight seconds: two adjacent requests then
        // legitimately resolve to the same keyframe, and a 2-second clip collapses to two or
        // three distinct frames pretending to be ten. Two unrelated short clips of the same
        // length would then agree on every "frame", pass the worst-frame veto because there was
        // nothing left for it to catch, and land in the tier this app pre-ticks.
        //
        // A twentieth of the duration keeps the window inside half the gap at every length.
        let tolerance = CMTime(seconds: min(0.4, seconds / 20), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        // One pass for all ten timestamps rather than ten separate seeks.
        //
        // `image(at:)` opens a decode session, seeks, decodes and tears down, so the loop that
        // was here paid that ten times per video — five thousand seeks across five hundred
        // clips where five hundred passes would do. `images(for:)` hands AVFoundation the whole
        // list and lets it walk the file once.
        let times = VideoSignature.samplePositions.map {
            CMTime(seconds: seconds * $0, preferredTimescale: 600)
        }

        var framesByTime: [Double: UInt64] = [:]
        for await result in generator.images(for: times) {
            guard
                case let .success(requestedTime: requested, image: image, actualTime: _) = result,
                let gray = GrayImageRenderer.render(image)
            else {
                // A signature with a gap in it would be compared against another video's frames
                // one position out, which is a worse answer than no answer.
                return nil
            }
            framesByTime[CMTimeGetSeconds(requested)] = PerceptualHasher.pHash(gray)
        }

        // Back into sample order: the stream does not promise one.
        var frames: [UInt64] = []
        frames.reserveCapacity(times.count)
        for time in times {
            guard let hash = framesByTime[CMTimeGetSeconds(time)] else { return nil }
            frames.append(hash)
        }

        let signature = VideoSignature(frameHashes: frames)

        // The belt to the tolerance's braces. A video can still resolve to a handful of
        // distinct frames for reasons that have nothing to do with the tolerance — a long
        // static shot, a slideshow export, a screen recording of a still page. `nil` means "not
        // enough evidence", which the pipeline already treats as "do not offer this", and that
        // is the correct answer rather than a confident wrong one.
        guard signature.carriesEnoughEvidence else { return nil }
        return signature
    }
}
