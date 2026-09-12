import Foundation
import DupeCore

/// One implementation, shared with the widget: the two must never disagree about what the
/// same number looks like.
enum ByteFormatting {

    static func string(_ bytes: Int64) -> String {
        ByteText.string(bytes)
    }
}

extension CategoryBreakdown.Category {

    var title: String {
        switch self {
        case .photos: return "Photos"
        case .videos: return "Videos"
        case .screenshots: return "Screenshots"
        case .livePhotos: return "Live Photos"
        case .documents: return "Documents"
        }
    }

    var symbolName: String {
        switch self {
        case .photos: return "photo"
        case .videos: return "film"
        case .screenshots: return "iphone.gen3"
        case .livePhotos: return "livephoto"
        case .documents: return "doc"
        }
    }
}
