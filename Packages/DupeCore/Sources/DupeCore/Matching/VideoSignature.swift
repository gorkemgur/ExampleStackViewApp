import Foundation

/// Perceptual hashes of frames sampled at fixed relative positions in a video.
public struct VideoSignature: Sendable, Hashable {

    /// Normalised timestamps the frames were taken from, e.g. 0.05, 0.15 ... 0.95.
    /// Spelled out rather than derived with `stride`, whose floating-point accumulation
    /// silently drops the last position.
    public static let samplePositions: [Double] = [0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95]

    public let frameHashes: [UInt64]

    public init(frameHashes: [UInt64]) {
        self.frameHashes = frameHashes
    }
}

/// Compares two videos frame-signature against frame-signature.
public enum VideoMatcher {

    public struct Comparison: Sendable, Hashable {
        /// Mean Hamming distance across the compared frames.
        public let averageDistance: Double
        /// Worst single frame. Guards against a signature that matches on average but has one
        /// completely different scene.
        public let worstDistance: Int
        /// Frame offset that produced this score.
        public let shift: Int
        public let comparedFrames: Int
    }

    /// Best alignment within +/- `maxShift` frames.
    ///
    /// The shift tolerance matters because the frame grabber snaps to the nearest keyframe,
    /// so the same footage encoded twice can land a sample on either side of a cut.
    ///
    /// - Returns: `nil` when the two signatures do not overlap by at least `minimumOverlap`
    ///   frames, which means there is not enough evidence to judge them.
    public static func compare(
        _ lhs: VideoSignature,
        _ rhs: VideoSignature,
        maxShift: Int = 1,
        minimumOverlap: Int = 3
    ) -> Comparison? {

        var best: Comparison?

        for shift in -maxShift...maxShift {
            var total = 0
            var worst = 0
            var count = 0

            for index in 0..<lhs.frameHashes.count {
                let other = index + shift
                guard other >= 0, other < rhs.frameHashes.count else { continue }
                let distance = hammingDistance(lhs.frameHashes[index], rhs.frameHashes[other])
                total += distance
                worst = max(worst, distance)
                count += 1
            }

            guard count >= minimumOverlap else { continue }

            let candidate = Comparison(
                averageDistance: Double(total) / Double(count),
                worstDistance: worst,
                shift: shift,
                comparedFrames: count
            )

            if best == nil || candidate.averageDistance < best!.averageDistance {
                best = candidate
            }
        }

        return best
    }

    /// Thresholds tuned to accept re-encodes while rejecting merely similar footage.
    public static func isDuplicate(
        _ comparison: Comparison,
        maximumAverage: Double = 8,
        maximumWorstFrame: Int = 16
    ) -> Bool {
        comparison.averageDistance <= maximumAverage && comparison.worstDistance <= maximumWorstFrame
    }
}
