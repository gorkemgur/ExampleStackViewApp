import Foundation

/// How alike two photographs have to be before the app is willing to call them the same shot.
///
/// This was a constant. It decides what the app shows you and what it stays quiet about, which
/// makes it the largest judgement in the product — and it was made once, by me, for everyone.
/// A holiday album full of near-identical sunsets and a camera roll of documents want different
/// answers, and only the person holding the phone knows which they have.
///
/// The trade is symmetric and stated plainly on screen: stricter finds fewer copies and asks
/// you fewer questions; looser finds more and hands you more judgement calls. No setting here
/// relaxes any of the four safety rules — a looser scan still never pre-ticks anything outside
/// the two tiers where deletion provably costs nothing.
public enum ScanStrictness: Int, Sendable, Hashable, Codable, CaseIterable {

    /// Only what is nearly unarguable. Misses the odd real duplicate.
    case strict
    /// The default.
    case balanced
    /// Casts wider. More to look through, more of it debatable.
    case loose

    public var configuration: ScanConfiguration {
        switch self {
        case .strict:
            return ScanConfiguration(
                nearExactDistance: 4,
                similarDistance: 8,
                videoAverageDistance: 6,
                videoWorstFrameDistance: 12
            )
        case .balanced:
            return .default
        case .loose:
            return ScanConfiguration(
                nearExactDistance: 8,
                similarDistance: 16,
                videoAverageDistance: 10,
                videoWorstFrameDistance: 20
            )
        }
    }

    public var title: String {
        switch self {
        case .strict: return "Strict"
        case .balanced: return "Balanced"
        case .loose: return "Loose"
        }
    }

    public var explanation: String {
        switch self {
        case .strict:
            return "Only pairs that are nearly unarguable. You will see fewer copies, and may miss a real one."
        case .balanced:
            return "The default. Catches re-sends and transcodes without filling the list with shots that merely rhyme."
        case .loose:
            return "Casts wider. Expect more to look through, and more of it to be your judgement rather than the app's."
        }
    }
}
