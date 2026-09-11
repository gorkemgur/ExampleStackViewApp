import Foundation

/// A reason a proposed deletion must not be executed.
public enum CleanupViolation: Sendable, Hashable, CustomStringConvertible {
    case keeperSelectedForDeletion(groupID: String, itemID: String)
    case groupFullyDeleted(groupID: String)
    case itemNotInAnyGroup(itemID: String)
    case itemInMultipleGroups(itemID: String)
    case unknownItem(itemID: String)

    public var description: String {
        switch self {
        case let .keeperSelectedForDeletion(groupID, itemID):
            return "group \(groupID) would delete its own keeper \(itemID)"
        case let .groupFullyDeleted(groupID):
            return "group \(groupID) would lose every copy"
        case let .itemNotInAnyGroup(itemID):
            return "\(itemID) is selected but belongs to no duplicate group"
        case let .itemInMultipleGroups(itemID):
            return "\(itemID) appears in more than one group"
        case let .unknownItem(itemID):
            return "\(itemID) is not in the index"
        }
    }
}

/// The last gate before anything is destroyed.
///
/// The planner already refuses to propose an unsafe deletion, but the selection the user hands
/// back has passed through UI state, so it is re-checked from scratch against the groups rather
/// than trusted. Nothing calls into PhotoKit or `FileManager` until this returns empty.
public enum CleanupValidator {

    public static func validate(
        selection: Set<String>,
        decisions: [GroupDecision],
        knownItemIDs: Set<String>
    ) -> [CleanupViolation] {

        var violations: [CleanupViolation] = []

        var owningGroup: [String: String] = [:]
        for decision in decisions {
            for itemID in [decision.keeperID] + decision.allCandidates {
                if owningGroup[itemID] != nil {
                    violations.append(.itemInMultipleGroups(itemID: itemID))
                } else {
                    owningGroup[itemID] = decision.id
                }
            }
        }

        for itemID in selection.sorted() {
            guard knownItemIDs.contains(itemID) else {
                violations.append(.unknownItem(itemID: itemID))
                continue
            }
            guard owningGroup[itemID] != nil else {
                violations.append(.itemNotInAnyGroup(itemID: itemID))
                continue
            }
        }

        for decision in decisions {
            if selection.contains(decision.keeperID) {
                violations.append(.keeperSelectedForDeletion(groupID: decision.id, itemID: decision.keeperID))
            }
            let allMembers = Set([decision.keeperID] + decision.allCandidates)
            if allMembers.isSubset(of: selection) {
                violations.append(.groupFullyDeleted(groupID: decision.id))
            }
        }

        return violations
    }

    /// Convenience for call sites that only care whether it is safe to proceed.
    public static func isSafe(
        selection: Set<String>,
        decisions: [GroupDecision],
        knownItemIDs: Set<String>
    ) -> Bool {
        validate(selection: selection, decisions: decisions, knownItemIDs: knownItemIDs).isEmpty
    }
}
