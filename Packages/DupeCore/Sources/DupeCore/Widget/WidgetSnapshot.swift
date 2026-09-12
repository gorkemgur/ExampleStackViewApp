import Foundation

/// What the app last knew, in the small shape a widget can render without doing any work.
///
/// A widget gets a few tens of milliseconds and no photo library access at all, so it reads a
/// value the app left behind rather than computing anything itself.
public struct WidgetSnapshot: Sendable, Codable, Equatable {

    public let totalCapacity: Int64
    public let availableCapacity: Int64
    /// What the photo library and granted folders account for.
    public let libraryBytes: Int64
    /// What the last scan said could be removed.
    public let reclaimableBytes: Int64
    public let duplicateCount: Int
    /// Of those, the ones that cost the user nothing.
    public let losslessBytes: Int64
    public let lastScanAt: Date?
    public let lifetimeReclaimedBytes: Int64
    public let updatedAt: Date

    public init(
        totalCapacity: Int64,
        availableCapacity: Int64,
        libraryBytes: Int64 = 0,
        reclaimableBytes: Int64 = 0,
        duplicateCount: Int = 0,
        losslessBytes: Int64 = 0,
        lastScanAt: Date? = nil,
        lifetimeReclaimedBytes: Int64 = 0,
        updatedAt: Date = Date()
    ) {
        self.totalCapacity = max(totalCapacity, 0)
        self.availableCapacity = max(min(availableCapacity, self.totalCapacity), 0)
        self.libraryBytes = max(libraryBytes, 0)
        self.reclaimableBytes = max(reclaimableBytes, 0)
        self.duplicateCount = max(duplicateCount, 0)
        self.losslessBytes = max(min(losslessBytes, self.reclaimableBytes), 0)
        self.lastScanAt = lastScanAt
        self.lifetimeReclaimedBytes = max(lifetimeReclaimedBytes, 0)
        self.updatedAt = updatedAt
    }

    public var usedCapacity: Int64 { totalCapacity - availableCapacity }

    public var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    public var hasScanned: Bool { lastScanAt != nil }

    /// Free space as it would be after acting on what the last scan found.
    public var projectedAvailableCapacity: Int64 {
        min(availableCapacity + reclaimableBytes, totalCapacity)
    }

    /// Something to show before the app has ever run. Deliberately not zeroed capacity, which
    /// would render as a full disk.
    public static let placeholder = WidgetSnapshot(
        totalCapacity: 128_000_000_000,
        availableCapacity: 34_000_000_000,
        libraryBytes: 61_000_000_000,
        reclaimableBytes: 4_300_000_000,
        duplicateCount: 128,
        losslessBytes: 3_100_000_000,
        lastScanAt: Date(timeIntervalSince1970: 1_750_000_000),
        lifetimeReclaimedBytes: 12_000_000_000,
        updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
    )
}

/// Where the app leaves that value and the widget picks it up.
///
/// A file in the shared container rather than shared `UserDefaults`: the write is atomic, so a
/// widget reloading mid-write reads the previous snapshot instead of half of the next one.
public struct WidgetSnapshotStore: Sendable {

    public static let defaultFileName = "widget-snapshot.json"

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `nil` when the App Group is not available — an unsigned build, or an entitlement that
    /// was never granted. The widget then shows its placeholder rather than lying.
    public init?(appGroupID: String, fileName: String = WidgetSnapshotStore.defaultFileName) {
        guard
            let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            return nil
        }
        fileURL = container.appendingPathComponent(fileName)
    }

    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// A partial update to the snapshot.
///
/// The app learns these things at different moments — capacity on every refresh, what a scan
/// found only when one finishes, the lifetime total only when something is deleted — so an
/// update carries what it knows and leaves everything else as it was.
public struct WidgetSnapshotUpdate: Sendable, Equatable {

    public var totalCapacity: Int64?
    public var availableCapacity: Int64?
    public var libraryBytes: Int64?
    public var reclaimableBytes: Int64?
    public var duplicateCount: Int?
    public var losslessBytes: Int64?
    /// Stamps `lastScanAt`. Set only by a scan that actually completed.
    public var markScanned: Bool
    public var lifetimeReclaimedBytes: Int64?

    public init(
        totalCapacity: Int64? = nil,
        availableCapacity: Int64? = nil,
        libraryBytes: Int64? = nil,
        reclaimableBytes: Int64? = nil,
        duplicateCount: Int? = nil,
        losslessBytes: Int64? = nil,
        markScanned: Bool = false,
        lifetimeReclaimedBytes: Int64? = nil
    ) {
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.libraryBytes = libraryBytes
        self.reclaimableBytes = reclaimableBytes
        self.duplicateCount = duplicateCount
        self.losslessBytes = losslessBytes
        self.markScanned = markScanned
        self.lifetimeReclaimedBytes = lifetimeReclaimedBytes
    }

    public func applied(to existing: WidgetSnapshot?, now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(
            totalCapacity: totalCapacity ?? existing?.totalCapacity ?? 0,
            availableCapacity: availableCapacity ?? existing?.availableCapacity ?? 0,
            libraryBytes: libraryBytes ?? existing?.libraryBytes ?? 0,
            reclaimableBytes: reclaimableBytes ?? existing?.reclaimableBytes ?? 0,
            duplicateCount: duplicateCount ?? existing?.duplicateCount ?? 0,
            losslessBytes: losslessBytes ?? existing?.losslessBytes ?? 0,
            lastScanAt: markScanned ? now : existing?.lastScanAt,
            lifetimeReclaimedBytes: lifetimeReclaimedBytes ?? existing?.lifetimeReclaimedBytes ?? 0,
            updatedAt: now
        )
    }
}
