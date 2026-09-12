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

    public static func sections(for result: ScanResult) -> [ReviewSection] {
        sections(candidates: result.candidates, items: result.items)
    }

    /// The same arrangement over a candidate list the caller has revised — after the user has
    /// chosen a different survivor, the offer is no longer the one the scan produced.
    public static func sections(
        candidates: [DeletionCandidate],
        items: [String: MediaItem]
    ) -> [ReviewSection] {
        var byTier: [RegretTier: [String: [DeletionCandidate]]] = [:]

        for candidate in candidates {
            byTier[candidate.tier, default: [:]][candidate.groupID, default: []].append(candidate)
        }

        return RegretTier.allCases.compactMap { tier -> ReviewSection? in
            guard let groupsForTier = byTier[tier], !groupsForTier.isEmpty else { return nil }

            let groups: [ReviewGroup] = groupsForTier
                .sorted { lhs, rhs in
                    let lhsBytes = lhs.value.reduce(Int64(0)) { $0 + $1.bytes }
                    let rhsBytes = rhs.value.reduce(Int64(0)) { $0 + $1.bytes }
                    return lhsBytes == rhsBytes ? lhs.key < rhs.key : lhsBytes > rhsBytes
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
