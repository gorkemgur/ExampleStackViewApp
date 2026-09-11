import Foundation

/// What deleting a selection actually gets the user back.
///
/// Split by *when* the space appears, because a photo library deletion does not free anything
/// until Recently Deleted is emptied, and an item whose original lives only in iCloud frees
/// nothing on the device at all. Reporting one number for all three is how a cleaner ends up
/// promising 12 GB and delivering none.
public struct SavingsBreakdown: Sendable, Hashable {

    /// Files in user-granted folders: gone the moment the deletion runs.
    public let immediateBytes: Int64
    /// Photo library items: reclaimed when Recently Deleted is emptied, otherwise after 30 days.
    public let deferredBytes: Int64
    /// Originals that are not on this device. Deleting frees iCloud storage, not local storage.
    public let cloudOnlyBytes: Int64

    public let itemCount: Int
    public let bytesByKind: [MediaKind: Int64]

    public static let empty = SavingsBreakdown(
        immediateBytes: 0,
        deferredBytes: 0,
        cloudOnlyBytes: 0,
        itemCount: 0,
        bytesByKind: [:]
    )

    public init(
        immediateBytes: Int64,
        deferredBytes: Int64,
        cloudOnlyBytes: Int64,
        itemCount: Int,
        bytesByKind: [MediaKind: Int64]
    ) {
        self.immediateBytes = immediateBytes
        self.deferredBytes = deferredBytes
        self.cloudOnlyBytes = cloudOnlyBytes
        self.itemCount = itemCount
        self.bytesByKind = bytesByKind
    }

    /// Everything that will eventually come back to the device.
    public var onDeviceBytes: Int64 { immediateBytes + deferredBytes }

    /// Every byte the selection accounts for, wherever it lives.
    public var totalBytes: Int64 { onDeviceBytes + cloudOnlyBytes }
}

public enum SavingsCalculator {

    public static func breakdown(for selection: Set<String>, items: [String: MediaItem]) -> SavingsBreakdown {
        var immediate: Int64 = 0
        var deferred: Int64 = 0
        var cloudOnly: Int64 = 0
        var byKind: [MediaKind: Int64] = [:]
        var count = 0

        for itemID in selection {
            guard let item = items[itemID] else { continue }
            count += 1

            // A Live Photo costs both its still and its movie, so both are reclaimed.
            let bytes = item.totalByteSize
            byKind[item.kind, default: 0] += bytes

            if !item.isLocallyAvailable {
                cloudOnly += bytes
                continue
            }

            switch item.source {
            case .fileFolder:
                immediate += bytes
            case .photoLibrary:
                deferred += bytes
            }
        }

        return SavingsBreakdown(
            immediateBytes: immediate,
            deferredBytes: deferred,
            cloudOnlyBytes: cloudOnly,
            itemCount: count,
            bytesByKind: byKind
        )
    }
}
