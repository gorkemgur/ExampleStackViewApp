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
