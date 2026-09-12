import Foundation

/// What the user decided that the engine did not.
///
/// The scorer picks a survivor and the planner picks what may be offered up, but both are
/// opinions about someone else's photographs. Two of those opinions have to be overrulable:
/// which copy stays, and whether a group is worth keeping at all.
public struct GroupOverride: Sendable, Hashable, Codable {

    /// The survivor the user chose instead of the scored one.
    public var keeperID: String?
    /// Set only by an explicit, per-group instruction. Nothing the app decides on its own — no
    /// pre-selection, no budget plan, no "select all" — may ever turn this on.
    public var deleteEverything: Bool

    public init(keeperID: String? = nil, deleteEverything: Bool = false) {
        self.keeperID = keeperID
        self.deleteEverything = deleteEverything
    }

    public var isEmpty: Bool { keeperID == nil && !deleteEverything }
}

/// Re-decides a group once the user has overruled it.
public enum GroupRevision {

    /// The decision as it stands after an override.
    ///
    /// Changing the survivor of an exact group is free: digest equality is transitive, so every
    /// member is interchangeable and any of them may stay.
    ///
    /// Changing it anywhere else costs the rest of the group. In a near-exact or similar group
    /// every member was measured against the seed and against nothing else, so once the user
    /// keeps some other copy, the only deletion still justified by direct evidence is the seed
    /// itself. The other members are dropped from the offer rather than quietly re-parented to
    /// a survivor nobody compared them with — which is the first rule, and the reason this
    /// function exists instead of a one-line swap.
    public static func apply(_ override: GroupOverride, to decision: GroupDecision) -> GroupDecision {
        guard let chosen = override.keeperID, chosen != decision.keeperID else { return decision }

        let members = [decision.keeperID] + decision.allCandidates
        guard members.contains(chosen) else { return decision }

        let remaining: [String]
        switch decision.relation {
        case .exact:
            remaining = members.filter { $0 != chosen }
        case .nearExact, .similar:
            remaining = [decision.keeperID]
        }

        // Nothing is pre-ticked after an override. The user is driving now, and a tick the app
        // placed under a different assumption is not an answer to the question they just asked.
        return GroupDecision(
            id: decision.id,
            relation: decision.relation,
            keeperID: chosen,
            autoSelectedForDeletion: [],
            manualReviewRequired: remaining.sorted()
        )
    }

    public static func apply(
        _ overrides: [String: GroupOverride],
        to decisions: [GroupDecision]
    ) -> [GroupDecision] {
        guard !overrides.isEmpty else { return decisions }
        return decisions.map { apply(overrides[$0.id] ?? GroupOverride(), to: $0) }
    }

    /// Members that stop being offered because the user kept something they were never compared
    /// with. The app says so rather than letting them disappear without explanation.
    public static func droppedMembers(
        _ override: GroupOverride,
        of decision: GroupDecision
    ) -> [String] {
        guard let chosen = override.keeperID, chosen != decision.keeperID else { return [] }

        let members = [decision.keeperID] + decision.allCandidates
        guard members.contains(chosen), decision.relation != .exact else { return [] }

        return members.filter { $0 != chosen && $0 != decision.keeperID }.sorted()
    }

    /// Every member of the group, survivor included.
    public static func members(of decision: GroupDecision) -> [String] {
        [decision.keeperID] + decision.allCandidates
    }
}
