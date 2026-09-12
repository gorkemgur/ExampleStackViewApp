import Foundation

/// Where a tap from outside the app should land.
///
/// The Live Activity and the widget both carry a link. Until now the app registered no URL
/// scheme and handled no URL, so tapping the running scan on the Lock Screen opened whatever
/// screen happened to be there — which is worse than offering no link at all.
///
/// Shared with the widget extension so the link that is published and the link that is handled
/// cannot drift apart.
enum DeepLink: Hashable {

    case scan

    static let scheme = "dupespace"

    init?(_ url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        // The host carries the destination; a trailing path is ignored rather than refused, so
        // an older widget's link still lands somewhere sensible.
        switch url.host() {
        case "scan": self = .scan
        default: return nil
        }
    }

    var url: URL {
        switch self {
        case .scan: return URL(string: "\(Self.scheme)://scan")!
        }
    }
}
