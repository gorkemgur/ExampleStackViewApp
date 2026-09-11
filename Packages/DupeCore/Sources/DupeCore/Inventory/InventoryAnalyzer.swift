import Foundation

/// A slice of the library, for the "what is actually taking up room" view.
public struct CategoryBreakdown: Sendable, Hashable, Identifiable {

    public enum Category: String, Sendable, Codable, CaseIterable {
        case photos
        case videos
        case screenshots
        case livePhotos
        case documents
    }

    public let category: Category
    public let itemCount: Int
    public let bytes: Int64

    public var id: String { category.rawValue }

    public init(category: Category, itemCount: Int, bytes: Int64) {
        self.category = category
        self.itemCount = itemCount
        self.bytes = bytes
    }
}

public enum InventoryAnalyzer {

    /// Each item lands in exactly one bucket, so the numbers add up to the library total.
    public static func category(for item: MediaItem) -> CategoryBreakdown.Category {
        if item.kind == .document { return .documents }
        if item.kind == .video { return .videos }
        if item.isScreenshot { return .screenshots }
        if item.isLivePhoto { return .livePhotos }
        return .photos
    }

    /// Ordered largest first, so the view opens on whatever is actually costing the user.
    public static func breakdown(for items: [MediaItem]) -> [CategoryBreakdown] {
        var counts: [CategoryBreakdown.Category: Int] = [:]
        var bytes: [CategoryBreakdown.Category: Int64] = [:]

        for item in items {
            let bucket = category(for: item)
            counts[bucket, default: 0] += 1
            bytes[bucket, default: 0] += item.totalByteSize
        }

        return counts.keys
            .map { CategoryBreakdown(category: $0, itemCount: counts[$0] ?? 0, bytes: bytes[$0] ?? 0) }
            .sorted { lhs, rhs in
                lhs.bytes == rhs.bytes
                    ? lhs.category.rawValue < rhs.category.rawValue
                    : lhs.bytes > rhs.bytes
            }
    }

    public static func totalBytes(_ items: [MediaItem]) -> Int64 {
        items.reduce(Int64(0)) { $0 + $1.totalByteSize }
    }

    public static func largest(_ items: [MediaItem], limit: Int) -> [MediaItem] {
        guard limit > 0 else { return [] }
        return items
            .sorted { lhs, rhs in
                lhs.totalByteSize == rhs.totalByteSize ? lhs.id < rhs.id : lhs.totalByteSize > rhs.totalByteSize
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Bytes whose originals are not on the device. Called out separately because deleting
    /// them frees iCloud storage and nothing else.
    public static func cloudOnlyBytes(_ items: [MediaItem]) -> Int64 {
        items.filter { !$0.isLocallyAvailable }.reduce(Int64(0)) { $0 + $1.totalByteSize }
    }
}
