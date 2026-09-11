import Foundation

/// How much a user stands to lose by deleting a candidate.
///
/// The whole product hangs off this ordering: the app does not ask "which of these are
/// duplicates", it asks "I need N gigabytes, what is the cheapest way to get there". Cheapest
/// means lowest tier first, and the two lowest tiers cost the user literally nothing.
public enum RegretTier: Int, Sendable, Codable, CaseIterable, Comparable {

    /// Byte-for-byte identical to the copy that stays. Deleting loses no information at all.
    case identical = 0

    /// A strictly worse re-encode — fewer pixels, no edits of its own — while the better
    /// original stays. Also a true zero-loss deletion.
    case inferiorCopy = 1

    /// Another frame of the same burst, where a sharper frame from that burst stays.
    case burstLeftover = 2

    /// Visually alike but not provably the same shot. Always a human decision.
    case similar = 3

    public static func < (lhs: RegretTier, rhs: RegretTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Tiers where deletion provably costs the user nothing, so they can be pre-selected.
    public static let losslessTiers: Set<RegretTier> = [.identical, .inferiorCopy]

    public var isLossless: Bool { Self.losslessTiers.contains(self) }
}

/// One item the engine is willing to delete, and the survivor that justifies it.
public struct DeletionCandidate: Sendable, Hashable, Identifiable {

    /// The item that would be deleted.
    public let id: String
    public let groupID: String
    /// The copy that stays. Every candidate was compared against this item directly.
    public let keeperID: String
    public let tier: RegretTier
    public let bytes: Int64
    /// Whether the planner is willing to tick this without the user looking at it.
    public let isPreSelected: Bool

    public init(
        id: String,
        groupID: String,
        keeperID: String,
        tier: RegretTier,
        bytes: Int64,
        isPreSelected: Bool
    ) {
        self.id = id
        self.groupID = groupID
        self.keeperID = keeperID
        self.tier = tier
        self.bytes = bytes
        self.isPreSelected = isPreSelected
    }
}

/// Turns planner decisions into tiered candidates.
public enum TierClassifier {

    public static func candidates(
        for decision: GroupDecision,
        group: DuplicateGroup,
        items: [String: MediaItem]
    ) -> [DeletionCandidate] {

        guard let keeper = items[decision.keeperID] else { return [] }
        let preSelected = Set(decision.autoSelectedForDeletion)

        return decision.allCandidates.compactMap { candidateID -> DeletionCandidate? in
            guard let item = items[candidateID] else { return nil }

            let tier = self.tier(for: item, keeper: keeper, relation: decision.relation)

            // A tier is a statement about information loss; being pre-selected is a stricter
            // claim the planner already made. Never widen it here.
            let isPreSelected = preSelected.contains(candidateID) && tier.isLossless

            return DeletionCandidate(
                id: candidateID,
                groupID: decision.id,
                keeperID: decision.keeperID,
                tier: tier,
                bytes: item.totalByteSize,
                isPreSelected: isPreSelected
            )
        }
        .sorted { lhs, rhs in
            lhs.tier == rhs.tier ? lhs.id < rhs.id : lhs.tier < rhs.tier
        }
    }

    private static func tier(
        for item: MediaItem,
        keeper: MediaItem,
        relation: DuplicateRelation
    ) -> RegretTier {
        switch relation {
        case .exact:
            return .identical

        case .nearExact:
            let strictlyWorse = keeper.pixelCount > item.pixelCount && !item.isEdited
            return strictlyWorse ? .inferiorCopy : .similar

        case .similar:
            // Frames of one burst are a known-safe case: the user pressed the shutter once.
            if let burst = item.burstIdentifier, burst == keeper.burstIdentifier {
                return .burstLeftover
            }
            return .similar
        }
    }

    public static func candidates(
        decisions: [GroupDecision],
        groups: [DuplicateGroup],
        items: [String: MediaItem]
    ) -> [DeletionCandidate] {
        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        return decisions.flatMap { decision -> [DeletionCandidate] in
            guard let group = groupsByID[decision.id] else { return [] }
            return candidates(for: decision, group: group, items: items)
        }
    }
}
