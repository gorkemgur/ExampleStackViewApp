import Foundation

/// Perceptual hashes of frames sampled at fixed relative positions in a video.
public struct VideoSignature: Sendable, Hashable, Codable {

    /// Normalised timestamps the frames were taken from, e.g. 0.05, 0.15 ... 0.95.
    /// Spelled out rather than derived with `stride`, whose floating-point accumulation
    /// silently drops the last position.
    public static let samplePositions: [Double] = [0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95]

    /// How many of the ten samples a signature has to resolve to *different* frames before it
    /// is worth comparing.
    ///
    /// Ten samples of the same frame is not ten observations, it is one, and the worst-frame
    /// veto — the whole reason this signature is ten numbers rather than one — has nothing left
    /// to veto. Six is the point at which the veto still has a majority of independent evidence
    /// behind it.
    public static let minimumDistinctFrames = 6

    public let frameHashes: [UInt64]

    public init(frameHashes: [UInt64]) {
        self.frameHashes = frameHashes
    }

    public var distinctFrameCount: Int { Set(frameHashes).count }

    /// False for a signature whose samples collapsed onto the same handful of frames. Refusing
    /// to judge is the right answer there: a video this app cannot describe is a video it must
    /// not offer to delete.
    public var carriesEnoughEvidence: Bool {
        distinctFrameCount >= Self.minimumDistinctFrames
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
    /// Defaults to no shift at all, and the reason is arithmetic rather than taste. The samples
    /// are taken at *normalised* positions — 5%, 15%, ... 95% of the duration — and the pipeline
    /// only ever compares two videos whose durations are within half a second of each other. So
    /// position `i` of one signature and position `i` of the other already describe the same
    /// moment of the same footage: shift 0 is the correct alignment by construction.
    ///
    /// Shifting by one therefore does not tolerate "a frame of drift", which is what this
    /// argument was documented as doing. It compares content a *tenth of the duration* apart —
    /// a full minute on a ten-minute recording. All it can do is hand every pair three chances
    /// to slip under the average threshold instead of one, and a duplicate finder that gets
    /// three attempts to say yes is a duplicate finder that says yes too often.
    ///
    /// Callers that sample at absolute offsets, where snapping to a keyframe really can move a
    /// sample into the next slot, can still ask for it.
    ///
    /// - Returns: `nil` when the two signatures do not overlap by at least `minimumOverlap`
    ///   frames, which means there is not enough evidence to judge them.
    public static func compare(
        _ lhs: VideoSignature,
        _ rhs: VideoSignature,
        maxShift: Int = 0,
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

            // Ranked on the worst frame first, then the average. Ranking on the average alone
            // let an alignment with a marginally lower mean but one wholly different scene
            // beat an alignment that passed both tests — the veto and the selection pulling in
            // opposite directions, with the veto losing.
            if best == nil || isBetter(candidate, than: best!) {
                best = candidate
            }
        }

        return best
    }

    private static func isBetter(_ candidate: Comparison, than incumbent: Comparison) -> Bool {
        if candidate.worstDistance != incumbent.worstDistance {
            return candidate.worstDistance < incumbent.worstDistance
        }
        return candidate.averageDistance < incumbent.averageDistance
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
