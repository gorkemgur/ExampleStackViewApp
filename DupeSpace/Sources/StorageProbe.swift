import Foundation
import DupeCore

/// Reads the device volume.
///
/// `volumeAvailableCapacityForImportantUsage` is the key Apple recommends for "can I write
/// something the user asked for": it includes space the system is willing to purge, so it
/// reads higher than the Settings app does. That is why the UI calls it an estimate.
enum StorageProbe {

    static func current() -> StorageSnapshot? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ]),
            let total = values.volumeTotalCapacity
        else {
            return nil
        }

        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return StorageSnapshot(totalCapacity: Int64(total), availableCapacity: available)
    }
}

enum ByteFormatting {

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        return formatter
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: max(bytes, 0))
    }
}
