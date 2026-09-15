import Foundation
import WidgetKit
import DupeCore

/// Leaves the widget something to show, and tells it to look.
///
/// Everything here is best-effort: a missing App Group means the widget falls back to its
/// placeholder, which is a far better outcome than the app refusing to work because a
/// secondary surface is unavailable.
enum WidgetPublisher {

    static func apply(_ update: WidgetSnapshotUpdate, now: Date = Date()) {
        guard let store = SharedContainer.snapshotStore() else { return }

        let merged = update.applied(to: store.read(), now: now)
        store.write(merged)

        WidgetCenter.shared.reloadAllTimelines()
    }

    static func publish(storage: StorageSnapshot?, libraryBytes: Int64) {
        apply(
            WidgetSnapshotUpdate(
                totalCapacity: storage?.totalCapacity,
                availableCapacity: storage?.availableCapacity,
                libraryBytes: libraryBytes
            )
        )
    }

    static func publish(scan: ScanResult) {
        let lossless = scan.candidates
            .filter { $0.tier.isLossless }
            .reduce(Int64(0)) { $0 + $1.bytes }

        apply(
            WidgetSnapshotUpdate(
                reclaimableBytes: scan.reclaimableBytes,
                duplicateCount: scan.candidates.count,
                losslessBytes: lossless,
                markScanned: true
            )
        )
    }

    static func publish(lifetimeReclaimedBytes: Int64) {
        apply(WidgetSnapshotUpdate(lifetimeReclaimedBytes: lifetimeReclaimedBytes))
    }
}
