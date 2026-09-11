import Foundation

/// What the device reports about its own volume.
///
/// `available` comes from `volumeAvailableCapacityForImportantUsage`, which counts space the
/// system would purge on demand. It is therefore an optimistic figure and is presented as an
/// estimate, never as a promise.
public struct StorageSnapshot: Sendable, Hashable {

    public let totalCapacity: Int64
    public let availableCapacity: Int64

    public init(totalCapacity: Int64, availableCapacity: Int64) {
        self.totalCapacity = max(totalCapacity, 0)
        self.availableCapacity = max(min(availableCapacity, self.totalCapacity), 0)
    }

    public var usedCapacity: Int64 { totalCapacity - availableCapacity }

    public var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    /// The same snapshot as it would look after reclaiming `bytes`.
    public func projecting(reclaimed bytes: Int64) -> StorageSnapshot {
        StorageSnapshot(
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity + max(bytes, 0)
        )
    }
}
