import Foundation
import DupeCore

enum ByteFormatting {

    private static let compact: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        // Without this the formatter writes "Zero KB", which reads as a formatting bug
        // rather than as a measurement.
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func string(_ bytes: Int64) -> String {
        compact.string(fromByteCount: max(bytes, 0))
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
