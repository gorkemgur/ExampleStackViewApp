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

    static func symbolName(for kind: MediaKind?) -> String {
        guard let kind else { return "square.stack" }
        switch kind {
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .document: return "doc"
        }
    }
}
