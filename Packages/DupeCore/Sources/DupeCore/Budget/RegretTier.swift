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
    /// True when no control that acts on many groups at once may tick this copy — however
    /// cheap its tier says it is.
    ///
    /// The tier answers "what information is lost". It does not answer "is this a copy this
    /// person has told us matters", and two of the planner's refusals are of the second kind:
    /// a favourite or album member, and a copy whose survivor exists only in iCloud. Both come
    /// out of `TierClassifier` wearing `.identical` — byte-for-byte the same file, nothing lost
    /// — which is true and beside the point.
    ///
    /// Without this the budget key ticked exactly the copies the planner had refused to
    /// pre-tick, three taps from deletion, under a confirmation reading "from N items that
    /// cost you nothing". `isPreSelected` could not stand in for it: nothing in a burst or a
    /// similar group is ever pre-selected, so a plan that required it would select nothing at
    /// the "+ bursts" and "+ similar" depths the user explicitly asked for.
    public let requiresHuman: Bool

    public init(
        id: String,
        groupID: String,
        keeperID: String,
        tier: RegretTier,
        bytes: Int64,
        isPreSelected: Bool,
        requiresHuman: Bool = false
    ) {
        self.id = id
        self.groupID = groupID
        self.keeperID = keeperID
        self.tier = tier
        self.bytes = bytes
        self.isPreSelected = isPreSelected
        self.requiresHuman = requiresHuman
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
                isPreSelected: isPreSelected,
                requiresHuman: requiresHuman(item: item, keeper: keeper)
            )
        }
        .sorted { lhs, rhs in
            lhs.tier == rhs.tier ? lhs.id < rhs.id : lhs.tier < rhs.tier
        }
    }

    /// The two refusals a tier cannot express.
    ///
    /// `CleanupPlanner` routes both of these to manual review and says why in its own words:
    /// "favourites and album members are never offered up without a human looking", and "a
    /// survivor that is only in iCloud is not a survivor the user still has to hand". Its third
    /// refusal — a copy carrying edits the survivor lacks — *is* expressible, and `tier(for:)`
    /// already files it under `.similar`, so it is not repeated here.
    ///
    /// Computed here rather than plumbed through from the planner because this is the one place
    /// that turns a decision into something a bulk control can act on, and a guard that lives
    /// anywhere else is a guard with a second path around it.
    private static func requiresHuman(item: MediaItem, keeper: MediaItem) -> Bool {
        item.isProtected || !keeper.isLocallyAvailable
    }

    private static func tier(
        for item: MediaItem,
        keeper: MediaItem,
        relation: DuplicateRelation
    ) -> RegretTier {
        switch relation {
        case .exact:
            // Byte equality covers the original resource. A copy carrying edits the survivor
            // does not have is not interchangeable with it, so it cannot be filed under
            // "loses nothing at all".
            if item.isEdited && !keeper.isEdited { return .similar }
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
        // Never traps: see the note in `ScanPipeline.run`. Group ids are derived from item
        // ids, so anything that can collide there can collide here.
        let groupsByID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return decisions.flatMap { decision -> [DeletionCandidate] in
            guard let group = groupsByID[decision.id] else { return [] }
            return candidates(for: decision, group: group, items: items)
        }
    }
}
