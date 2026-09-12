import Foundation
import DupeCore

/// What to call a kind of thing on screen, and which glyph stands for it.
///
/// One place, because the same three words appear on the review filter, on a thumbnail badge
/// and in the breakdown card, and three files each inventing their own is how "Photos",
/// "Photos & videos" and "Images" end up on one screen.
enum KindCopy {

    static func title(for kind: MediaKind?) -> String {
        guard let kind else { return "Everything" }
        switch kind {
        case .image: return "Photos"
        case .video: return "Videos"
        case .document: return "Files"
        }
    }

    /// The stable word for a kind in an accessibility identifier.
    ///
    /// `MediaKind` is an `Int` enum, so `rawValue` gives `review.kindsection.1` — a contract
    /// the UI tests have to read the enum's declaration order to honour, and one that silently
    /// rebinds if a case is ever inserted.
    static func slug(for kind: MediaKind?) -> String {
        guard let kind else { return "all" }
        switch kind {
        case .image: return "image"
        case .video: return "video"
        case .document: return "document"
        }
    }

    static func symbolName(for kind: MediaKind?) -> String {
        guard let kind else { return "square.stack" }
        switch kind {
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .document: return "doc"
        }
    }
}
