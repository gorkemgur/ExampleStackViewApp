import Foundation

/// One survivor and the copies offered up next to it, within a single tier.
public struct ReviewGroup: Sendable, Identifiable, Equatable {

    public let id: String
    public let tier: RegretTier
    public let keeper: MediaItem
    public let candidates: [DeletionCandidate]
    public let items: [MediaItem]

    public init(
        id: String,
        tier: RegretTier,
        keeper: MediaItem,
        candidates: [DeletionCandidate],
        items: [MediaItem]
    ) {
        self.id = id
        self.tier = tier
        self.keeper = keeper
        self.candidates = candidates
        self.items = items
    }

    public var bytes: Int64 { candidates.reduce(Int64(0)) { $0 + $1.bytes } }
    public var candidateIDs: [String] { candidates.map(\.id) }

    /// True when this group holds the same picture in the photo library *and* in a folder the
    /// user handed over.
    ///
    /// The one comparison nothing else on the phone makes. Apple's Duplicates looks inside the
    /// photo library and stops at its edge; a file manager looks at files and cannot see the
    /// library at all. So the copy you exported to Files, or saved out of a chat, or pulled off
    /// a camera into a folder, is invisible to both — and it is the duplicate people are most
    /// sure they do not have.
    ///
    /// It was invisible to this app too, for a subtler reason: the two halves fingerprinted
    /// pictures with two different downsamplers, so the same photograph indexed both ways did
    /// not necessarily land on the same fingerprint. That is fixed; this is the flag that says
    /// so on screen, and the sentence beside it is the only reason a person would believe the
    /// app looked anywhere their own eyes had not.
    public var spansLibraryAndFolders: Bool {
        var sawLibrary = false
        var sawFolder = false
        for item in items {
            switch item.source {
            case .photoLibrary: sawLibrary = true
            case .fileFolder: sawFolder = true
            }
            if sawLibrary && sawFolder { return true }
        }
        return false
    }
}

/// A tier's worth of groups.
public struct ReviewSection: Sendable, Identifiable, Equatable {

    public let tier: RegretTier
    public let groups: [ReviewGroup]

    public var id: Int { tier.rawValue }

    public init(tier: RegretTier, groups: [ReviewGroup]) {
        self.tier = tier
        self.groups = groups
    }

    public var bytes: Int64 { groups.reduce(Int64(0)) { $0 + $1.bytes } }
    public var itemCount: Int { groups.reduce(0) { $0 + $1.candidates.count } }
    public var candidateIDs: [String] { groups.flatMap(\.candidateIDs) }
}

/// Arranges a scan result for reading.
///
/// Candidates are filed by tier first, because that is the axis the user makes decisions on.
/// A single duplicate group can straddle two tiers — one member a strictly worse re-encode,
/// another merely similar — so it appears in each, carrying only the candidates that belong
/// there. The survivor is shown in both; it is the same photo either way.
public enum ReviewBuilder {

    /// What decides the order of the groups inside a rung.
    ///
    /// The list only ever had one axis of its own: bytes, largest first. That is the right
    /// default — the screen exists to free space — but it made date unaskable, and date is the
    /// instinct people actually arrive with. "The old ones" is how someone thinks about a
    /// library they have not looked at in four years, and `creationDate` was sitting on every
    /// item, computed and unused by this screen.
    public enum Order: String, Sendable, CaseIterable {
        /// Largest first. Fewest taps to the target.
        case biggest
        /// Oldest first, by the survivor's own date.
        case oldest
        /// Newest first, for the opposite instinct: the pile that built up this month.
        case newest

        public var title: String {
            switch self {
            case .biggest: return "Biggest"
            case .oldest: return "Oldest"
            case .newest: return "Newest"
            }
        }
    }

    public static func sections(for result: ScanResult, order: Order = .biggest) -> [ReviewSection] {
        sections(candidates: result.candidates, items: result.items, order: order)
    }

    /// The same arrangement over a candidate list the caller has revised — after the user has
    /// chosen a different survivor, the offer is no longer the one the scan produced.
    public static func sections(
        candidates: [DeletionCandidate],
        items: [String: MediaItem],
        order: Order = .biggest
    ) -> [ReviewSection] {
        var byTier: [RegretTier: [String: [DeletionCandidate]]] = [:]

        for candidate in candidates {
            byTier[candidate.tier, default: [:]][candidate.groupID, default: []].append(candidate)
        }

        return RegretTier.allCases.compactMap { tier -> ReviewSection? in
            guard let groupsForTier = byTier[tier], !groupsForTier.isEmpty else { return nil }

            let groups: [ReviewGroup] = groupsForTier
                .sorted { lhs, rhs in
                    Self.isOrdered(lhs, before: rhs, by: order, items: items)
                }
                .compactMap { groupID, candidates -> ReviewGroup? in
                    guard
                        let keeperID = candidates.first?.keeperID,
                        let keeper = items[keeperID]
                    else {
                        return nil
                    }

                    let ordered = candidates.sorted { lhs, rhs in
                        lhs.bytes == rhs.bytes ? lhs.id < rhs.id : lhs.bytes > rhs.bytes
                    }
                    let members = ordered.compactMap { items[$0.id] }

                    return ReviewGroup(
                        id: "\(tier.rawValue)|\(groupID)",
                        tier: tier,
                        keeper: keeper,
                        candidates: ordered,
                        items: members
                    )
                }

            guard !groups.isEmpty else { return nil }
            return ReviewSection(tier: tier, groups: groups)
        }
    }

    /// Group ordering, with the group id as the final tie-break in every case.
    ///
    /// The tie-break is not a detail: without it two groups of the same size — which is the
    /// common case for a burst — could swap places between two reads of the same data, and the
    /// list would shuffle under the user's finger as they ticked things.
    private static func isOrdered(
        _ lhs: (key: String, value: [DeletionCandidate]),
        before rhs: (key: String, value: [DeletionCandidate]),
        by order: Order,
        items: [String: MediaItem]
    ) -> Bool {
        switch order {
        case .biggest:
            let lhsBytes = lhs.value.reduce(Int64(0)) { $0 + $1.bytes }
            let rhsBytes = rhs.value.reduce(Int64(0)) { $0 + $1.bytes }
            return lhsBytes == rhsBytes ? lhs.key < rhs.key : lhsBytes > rhsBytes

        case .oldest, .newest:
            // The survivor's date, because that is the photograph the group is *about*. A
            // re-send arrives years after the original and sorting by it would file the group
            // under the day someone forwarded it.
            let lhsDate = date(of: lhs.value, items: items)
            let rhsDate = date(of: rhs.value, items: items)

            // A group with no date at all goes last either way. Undated items are a real case —
            // a file in a granted folder can have no creation date — and putting them first in
            // "oldest" would hand the top of the list to the least informative rows.
            switch (lhsDate, rhsDate) {
            case let (left?, right?):
                if left == right { return lhs.key < rhs.key }
                return order == .oldest ? left < right : left > right
            case (nil, nil):
                return lhs.key < rhs.key
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }
    }

    private static func date(of candidates: [DeletionCandidate], items: [String: MediaItem]) -> Date? {
        guard let keeperID = candidates.first?.keeperID else { return nil }
        return items[keeperID]?.creationDate
    }
}

extension ReviewGroup {

    /// The same group with `ids` taken out. `nil` when there is nothing left to offer, which
    /// is what happens once every copy in it has actually been deleted.
    public func removing(_ ids: Set<String>) -> ReviewGroup? {
        guard !ids.isEmpty else { return self }

        let remaining = candidates.filter { !ids.contains($0.id) }
        guard !remaining.isEmpty else { return nil }

        let remainingIDs = Set(remaining.map(\.id))
        return ReviewGroup(
            id: id,
            tier: tier,
            keeper: keeper,
            candidates: remaining,
            items: items.filter { remainingIDs.contains($0.id) }
        )
    }
}

extension ReviewSection {

    public func removing(_ ids: Set<String>) -> ReviewSection? {
        guard !ids.isEmpty else { return self }

        let remaining = groups.compactMap { $0.removing(ids) }
        guard !remaining.isEmpty else { return nil }

        return ReviewSection(tier: tier, groups: remaining)
    }
}
