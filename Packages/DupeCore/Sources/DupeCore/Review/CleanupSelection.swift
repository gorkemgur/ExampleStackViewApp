import Foundation

/// What the user has ticked.
///
/// Held as a value so a view can hand it around freely, and deliberately dumb: it never
/// decides what *may* be selected. That question belongs to `CleanupValidator`, which is run
/// against the final set before anything is destroyed, rather than to whatever path through
/// the UI produced it.
public struct CleanupSelection: Sendable, Equatable {

    public private(set) var selectedIDs: Set<String>

    public init(selectedIDs: Set<String> = []) {
        self.selectedIDs = selectedIDs
    }

    /// The app's opening state: everything the engine is willing to vouch for, and nothing else.
    public static func preSelected(from candidates: [DeletionCandidate]) -> CleanupSelection {
        CleanupSelection(selectedIDs: Set(candidates.filter(\.isPreSelected).map(\.id)))
    }

    public var isEmpty: Bool { selectedIDs.isEmpty }
    public var count: Int { selectedIDs.count }

    public func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    public mutating func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    public mutating func setSelected(_ isSelected: Bool, for ids: [String]) {
        if isSelected {
            selectedIDs.formUnion(ids)
        } else {
            selectedIDs.subtract(ids)
        }
    }

    public mutating func replace(with ids: Set<String>) {
        selectedIDs = ids
    }

    public mutating func clear() {
        selectedIDs.removeAll()
    }

    /// True when every one of `ids` is ticked. Used for the "whole section" control, which
    /// must not read as on while part of the section is off.
    public func containsAll(_ ids: [String]) -> Bool {
        guard !ids.isEmpty else { return false }
        return ids.allSatisfy { selectedIDs.contains($0) }
    }
}
