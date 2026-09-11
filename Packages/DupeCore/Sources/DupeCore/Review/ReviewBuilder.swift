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
        var byTier: [RegretTier: [String: [DeletionCandidate]]] = [:]

        for candidate in result.candidates {
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
                        let keeper = result.items[keeperID]
                    else {
                        return nil
                    }

                    let ordered = candidates.sorted { lhs, rhs in
                        lhs.bytes == rhs.bytes ? lhs.id < rhs.id : lhs.bytes > rhs.bytes
                    }
                    let members = ordered.compactMap { result.items[$0.id] }

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
