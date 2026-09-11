import Foundation
import DupeCore

/// Reads the device volume.
///
/// `volumeAvailableCapacityForImportantUsage` is the key Apple recommends for "can I write
/// something the user asked for": it counts space the system is willing to purge, so it reads
/// higher than Settings does. That is why the UI calls it an estimate rather than a number.
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
