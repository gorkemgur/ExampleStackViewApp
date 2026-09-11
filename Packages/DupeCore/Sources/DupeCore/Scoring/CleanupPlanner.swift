import Foundation

/// What the engine proposes to do with one duplicate group.
public struct GroupDecision: Sendable, Hashable, Identifiable {

    public let id: String
    public let relation: DuplicateRelation
    /// The copy that stays. Never appears in either deletion list.
    public let keeperID: String
    /// Pre-ticked in the UI. Only ever populated when the evidence is strong enough that a
    /// mistake is not possible in principle, not merely unlikely.
    public let autoSelectedForDeletion: [String]
    /// Shown unticked; the user has to look at these.
    public let manualReviewRequired: [String]

    public init(
        id: String,
        relation: DuplicateRelation,
        keeperID: String,
        autoSelectedForDeletion: [String],
        manualReviewRequired: [String]
    ) {
        self.id = id
        self.relation = relation
        self.keeperID = keeperID
        self.autoSelectedForDeletion = autoSelectedForDeletion
        self.manualReviewRequired = manualReviewRequired
    }

    public var allCandidates: [String] { autoSelectedForDeletion + manualReviewRequired }
}

/// Decides, for each group, what survives and what may be offered up automatically.
public enum CleanupPlanner {

    public static func decide(
        group: DuplicateGroup,
        items: [String: MediaItem],
        weights: KeeperWeights = .default
    ) -> GroupDecision? {

        let members = group.itemIDs.compactMap { items[$0] }
        guard members.count > 1 else { return nil }

        let keeper: MediaItem?
        switch group.relation {
        case .exact:
            // Digest equality is transitive, so any member is a valid survivor and we are
            // free to pick the best one.
            keeper = KeeperScorer.keeper(among: members, weights: weights)
        case .nearExact, .similar:
            // Every other member was measured against the seed and only against the seed.
            // Keeping anything else would delete photos nobody compared to the survivor.
            keeper = members.first { $0.id == group.seedID }
        }
        guard let keeper else { return nil }

        var autoSelected: [String] = []
        var manual: [String] = []

        for member in members where member.id != keeper.id {
            if member.isProtected {
                // Favourites and album members are never offered up without a human looking.
                manual.append(member.id)
                continue
            }

            switch group.relation {
            case .exact:
                autoSelected.append(member.id)
            case .nearExact:
                // A re-encode is only safe to pre-tick when the survivor is strictly better
                // in every way that cannot be recovered: more pixels, no edits to lose, and
                // actually present so the user is not left with a cloud-only survivor.
                let keeperIsStrictlyBetter = keeper.pixelCount > member.pixelCount
                    && keeper.isLocallyAvailable
                    && !member.isEdited
                if keeperIsStrictlyBetter {
                    autoSelected.append(member.id)
                } else {
                    manual.append(member.id)
                }
            case .similar:
                manual.append(member.id)
            }
        }

        return GroupDecision(
            id: group.id,
            relation: group.relation,
            keeperID: keeper.id,
            autoSelectedForDeletion: autoSelected.sorted(),
            manualReviewRequired: manual.sorted()
        )
    }

    public static func decide(
        groups: [DuplicateGroup],
        items: [String: MediaItem],
        weights: KeeperWeights = .default
    ) -> [GroupDecision] {
        groups.compactMap { decide(group: $0, items: items, weights: weights) }
    }
}
