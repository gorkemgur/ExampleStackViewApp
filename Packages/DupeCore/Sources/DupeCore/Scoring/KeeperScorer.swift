import Foundation

/// Relative importance of each signal when deciding which copy survives.
public struct KeeperWeights: Sendable, Hashable {

    /// Favourited or filed into an album. Large enough that a protected item outranks any
    /// combination of quality signals.
    public var protectedItem: Double
    public var edited: Double
    public var highestResolution: Double
    public var largestFile: Double
    public var livePhoto: Double
    public var userLibraryOriginal: Double
    public var oldestCapture: Double
    public var locationMetadata: Double
    public var screenshot: Double
    public var cloudOnly: Double

    public static let `default` = KeeperWeights(
        protectedItem: 1000,
        edited: 300,
        highestResolution: 200,
        largestFile: 100,
        livePhoto: 150,
        userLibraryOriginal: 80,
        oldestCapture: 50,
        locationMetadata: 40,
        screenshot: -100,
        cloudOnly: -25
    )

    public init(
        protectedItem: Double,
        edited: Double,
        highestResolution: Double,
        largestFile: Double,
        livePhoto: Double,
        userLibraryOriginal: Double,
        oldestCapture: Double,
        locationMetadata: Double,
        screenshot: Double,
        cloudOnly: Double
    ) {
        self.protectedItem = protectedItem
        self.edited = edited
        self.highestResolution = highestResolution
        self.largestFile = largestFile
        self.livePhoto = livePhoto
        self.userLibraryOriginal = userLibraryOriginal
        self.oldestCapture = oldestCapture
        self.locationMetadata = locationMetadata
        self.screenshot = screenshot
        self.cloudOnly = cloudOnly
    }
}

/// Ranks the members of a duplicate group so the best copy is the one that stays.
public enum KeeperScorer {

    /// Scores every item relative to the others in the same group.
    public static func scores(for items: [MediaItem], weights: KeeperWeights = .default) -> [String: Double] {
        guard !items.isEmpty else { return [:] }

        let bestPixelCount = items.map(\.pixelCount).max() ?? 0
        let largestSize = items.map(\.totalByteSize).max() ?? 0
        let earliestDate = items.compactMap(\.creationDate).min()

        var result: [String: Double] = [:]
        for item in items {
            var score = 0.0
            if item.isProtected { score += weights.protectedItem }
            if item.isEdited { score += weights.edited }
            if item.pixelCount > 0 && item.pixelCount == bestPixelCount { score += weights.highestResolution }
            if item.totalByteSize > 0 && item.totalByteSize == largestSize { score += weights.largestFile }
            if item.isLivePhoto { score += weights.livePhoto }
            if item.isUserLibraryOriginal { score += weights.userLibraryOriginal }
            if let earliestDate, let date = item.creationDate, date == earliestDate { score += weights.oldestCapture }
            if item.hasLocationMetadata { score += weights.locationMetadata }
            if item.isScreenshot { score += weights.screenshot }
            if !item.isLocallyAvailable { score += weights.cloudOnly }
            result[item.id] = score
        }
        return result
    }

    /// The item that should survive. Ties break towards the larger file, then the earlier
    /// capture, then the lexicographically smaller id, so the answer never depends on the
    /// order items happened to be enumerated in.
    public static func keeper(among items: [MediaItem], weights: KeeperWeights = .default) -> MediaItem? {
        guard !items.isEmpty else { return nil }
        let scores = scores(for: items, weights: weights)

        return items.max { lhs, rhs in
            let lhsScore = scores[lhs.id] ?? 0
            let rhsScore = scores[rhs.id] ?? 0
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            if lhs.totalByteSize != rhs.totalByteSize { return lhs.totalByteSize < rhs.totalByteSize }
            switch (lhs.creationDate, rhs.creationDate) {
            case let (left?, right?) where left != right:
                return left > right
            default:
                break
            }
            return lhs.id > rhs.id
        }
    }
}

extension KeeperScorer {

    /// A library-wide ranking, used to pick which item a similar-group forms around.
    ///
    /// `scores(for:)` is relative to one group, which is the right answer once a group exists
    /// but useless while deciding what the groups should be. This ordering is absolute and
    /// deterministic: protection dominates everything, then quality signals, then raw size.
    public static func globalRank(for item: MediaItem) -> Double {
        var rank = 0.0
        if item.isProtected { rank += 1_000_000 }
        if item.isEdited { rank += 300_000 }
        if item.isLivePhoto { rank += 150_000 }
        if item.isUserLibraryOriginal { rank += 80_000 }
        if item.hasLocationMetadata { rank += 40_000 }
        if item.isScreenshot { rank -= 100_000 }
        if !item.isLocallyAvailable { rank -= 25_000 }

        // Tie-breakers, scaled so they can never overturn a categorical signal above.
        //
        // They did not used to be. `pixelCount / 1_000` gives a 48 MP ProRAW 48,000 and a
        // 15,000x3,500 panorama 52,500 — more than the 40,000 for location metadata and twice
        // the 25,000 penalty for an original that is not even on the device. So a panorama with
        // no location outranked a photo with one, and any image over 25 MP cancelled the
        // cloud-only penalty outright. That is not a tie-breaker, it is a categorical signal
        // wearing a tie-breaker's clothes, and it decides the seed of every similar group —
        // which is the copy this app steers the user into keeping.
        //
        // Divided until they cannot reach 1.0 at any size a camera produces: a 200 MP frame
        // contributes 0.2, a 100 GB file 0.01. Pixels still outrank bytes, which is the order
        // the two were written in.
        rank += Double(item.pixelCount) / 1_000_000_000
        rank += Double(item.totalByteSize) / 10_000_000_000_000
        return rank
    }

    public static func globalRanks(for items: [MediaItem]) -> [String: Double] {
        var ranks: [String: Double] = [:]
        for item in items {
            ranks[item.id] = globalRank(for: item)
        }
        return ranks
    }
}
