import Foundation

/// What one tier contributed, frozen at the time of a scan.
public struct TierTotal: Sendable, Codable, Hashable, Identifiable {

    public let tier: RegretTier
    public let itemCount: Int
    public let bytes: Int64

    public var id: Int { tier.rawValue }

    public init(tier: RegretTier, itemCount: Int, bytes: Int64) {
        self.tier = tier
        self.itemCount = itemCount
        self.bytes = bytes
    }
}

/// A scan that happened.
public struct ScanRecord: Sendable, Codable, Hashable, Identifiable {

    public let id: UUID
    public let startedAt: Date
    public let finishedAt: Date
    public let itemsScanned: Int
    public let groupsFound: Int
    public let reclaimableBytes: Int64
    public let tiers: [TierTotal]
    /// Items deliberately left unread because their originals live in iCloud.
    public let cloudOnlyCount: Int

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        itemsScanned: Int,
        groupsFound: Int,
        reclaimableBytes: Int64,
        tiers: [TierTotal],
        cloudOnlyCount: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.itemsScanned = itemsScanned
        self.groupsFound = groupsFound
        self.reclaimableBytes = reclaimableBytes
        self.tiers = tiers
        self.cloudOnlyCount = cloudOnlyCount
    }

    public var duration: TimeInterval { max(finishedAt.timeIntervalSince(startedAt), 0) }
    public var foundSomething: Bool { groupsFound > 0 }
}

/// One photo that was removed, and the one that was kept in its place.
///
/// The survivor's name is stored rather than looked up later: the point of a receipt is that
/// it still reads correctly after the library has moved on.
public struct DeletedItemRecord: Sendable, Codable, Hashable, Identifiable {

    public let id: String
    public let displayName: String
    public let bytes: Int64
    public let kind: MediaKind
    public let tier: RegretTier
    public let keptInsteadName: String

    public init(
        id: String,
        displayName: String,
        bytes: Int64,
        kind: MediaKind,
        tier: RegretTier,
        keptInsteadName: String
    ) {
        self.id = id
        self.displayName = displayName
        self.bytes = bytes
        self.kind = kind
        self.tier = tier
        self.keptInsteadName = keptInsteadName
    }
}

/// A deletion that happened.
public struct DeletionRecord: Sendable, Codable, Hashable, Identifiable {

    /// How long iOS keeps deleted photos before the space actually returns.
    public static let recentlyDeletedWindow: TimeInterval = 30 * 24 * 60 * 60

    public let id: UUID
    public let performedAt: Date
    public let items: [DeletedItemRecord]
    /// Space that returns once Recently Deleted is emptied.
    public let deferredBytes: Int64
    /// Space that returned immediately.
    public let immediateBytes: Int64

    public init(
        id: UUID = UUID(),
        performedAt: Date,
        items: [DeletedItemRecord],
        deferredBytes: Int64,
        immediateBytes: Int64
    ) {
        self.id = id
        self.performedAt = performedAt
        self.items = items
        self.deferredBytes = deferredBytes
        self.immediateBytes = immediateBytes
    }

    public var itemCount: Int { items.count }
    public var reclaimedBytes: Int64 { deferredBytes + immediateBytes }

    /// When the photo-library half stops being recoverable. `nil` when nothing went to
    /// Recently Deleted in the first place.
    public var recoverableUntil: Date? {
        guard deferredBytes > 0 else { return nil }
        return performedAt.addingTimeInterval(Self.recentlyDeletedWindow)
    }

    public func isStillRecoverable(at date: Date) -> Bool {
        guard let deadline = recoverableUntil else { return false }
        return date < deadline
    }

    /// Anything above the two lossless tiers was a judgement call, and the receipt says so.
    public var judgementCallCount: Int {
        items.filter { !$0.tier.isLossless }.count
    }
}

/// One merged, newest-first feed of everything that has happened.
public enum HistoryEntry: Sendable, Hashable, Identifiable {

    case scan(ScanRecord)
    case deletion(DeletionRecord)

    public var id: String {
        switch self {
        case let .scan(record): return "scan-\(record.id.uuidString)"
        case let .deletion(record): return "deletion-\(record.id.uuidString)"
        }
    }

    public var date: Date {
        switch self {
        case let .scan(record): return record.finishedAt
        case let .deletion(record): return record.performedAt
        }
    }
}

/// Everything the app remembers about what it has done.
///
/// Most storage cleaners never tell you what they removed. This one keeps a receipt: what went,
/// what stayed in its place, what it was worth, and how long it can still be undone from
/// Recently Deleted.
public struct HistoryLog: Sendable, Codable, Equatable {

    /// Enough to be useful, bounded so the file cannot grow without limit.
    public static let maximumScans = 50
    public static let maximumDeletions = 200

    public private(set) var scans: [ScanRecord]
    public private(set) var deletions: [DeletionRecord]

    public init(scans: [ScanRecord] = [], deletions: [DeletionRecord] = []) {
        self.scans = Self.trimmed(scans, by: \.finishedAt, to: Self.maximumScans)
        self.deletions = Self.trimmed(deletions, by: \.performedAt, to: Self.maximumDeletions)
    }

    public var isEmpty: Bool { scans.isEmpty && deletions.isEmpty }

    public mutating func record(_ scan: ScanRecord) {
        scans = Self.trimmed(scans + [scan], by: \.finishedAt, to: Self.maximumScans)
    }

    public mutating func record(_ deletion: DeletionRecord) {
        deletions = Self.trimmed(deletions + [deletion], by: \.performedAt, to: Self.maximumDeletions)
    }

    public mutating func clear() {
        scans = []
        deletions = []
    }

    /// Newest first, scans and deletions interleaved.
    public var timeline: [HistoryEntry] {
        let entries = scans.map(HistoryEntry.scan) + deletions.map(HistoryEntry.deletion)
        return entries.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date > rhs.date
        }
    }

    public var totalReclaimedBytes: Int64 {
        deletions.reduce(Int64(0)) { $0 + $1.reclaimedBytes }
    }

    public var totalItemsDeleted: Int {
        deletions.reduce(0) { $0 + $1.itemCount }
    }

    /// Deletions whose photo-library half can still be undone from Recently Deleted.
    public func recoverableDeletions(at date: Date) -> [DeletionRecord] {
        deletions
            .filter { $0.isStillRecoverable(at: date) }
            .sorted { $0.performedAt > $1.performedAt }
    }

    private static func trimmed<T>(
        _ values: [T],
        by date: KeyPath<T, Date>,
        to limit: Int
    ) -> [T] {
        values
            .sorted { $0[keyPath: date] > $1[keyPath: date] }
            .prefix(limit)
            .map { $0 }
    }
}
