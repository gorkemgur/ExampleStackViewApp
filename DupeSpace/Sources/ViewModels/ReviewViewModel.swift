import Combine
import Foundation
import DupeCore

@MainActor
final class ReviewViewModel: ObservableObject {

    @Published private(set) var selection: CleanupSelection
    @Published private(set) var isDeleting = false
    @Published private(set) var outcome: DeletionOutcome?
    @Published private(set) var failure: String?

    /// Target for the "I need this much back" slider, in bytes.
    @Published var budgetBytes: Double = 0
    /// How far the slider is allowed to reach. Starts at the tiers that cost the user nothing.
    @Published var budgetDepth: RegretTier = .inferiorCopy

    /// Items that have actually been removed. Kept so the list stops offering copies that no
    /// longer exist the moment a deletion succeeds, rather than leaving the user staring at
    /// rows that would fail if tapped.
    @Published private(set) var deletedIDs: Set<String> = []

    /// Where the user has overruled the engine: a different survivor, or a group they want gone
    /// entirely. Keyed by group id.
    @Published private(set) var overrides: [String: GroupOverride] = [:]

    let result: ScanResult

    private let allSections: [ReviewSection]
    private let deleter: MediaDeleting
    private weak var history: (any HistoryRecording)?

    init(result: ScanResult, deleter: MediaDeleting, history: (any HistoryRecording)? = nil) {
        self.result = result
        self.deleter = deleter
        self.history = history
        self.allSections = ReviewBuilder.sections(for: result)
        self.selection = .preSelected(from: result.candidates)

        // The slider opens where the app's own suggestion already sits. Starting at zero made
        // the card say "nothing is selected by a plan of zero" directly above a bar saying
        // three things were selected — the screen contradicting itself on first sight.
        budgetBytes = Double(
            result.candidates.filter(\.isPreSelected).reduce(Int64(0)) { $0 + $1.bytes }
        )
    }

    var sections: [ReviewSection] {
        guard !overrides.isEmpty else {
            return allSections.compactMap { $0.removing(deletedIDs) }
        }
        return ReviewBuilder
            .sections(candidates: revisedCandidates, items: result.items)
            .compactMap { $0.removing(deletedIDs) }
    }

    /// The decisions as they stand after the user has overruled any of them.
    var decisions: [GroupDecision] {
        GroupRevision.apply(overrides, to: result.decisions)
    }

    /// Groups the user has explicitly asked to remove entirely. The only thing that may empty a
    /// group, and it can only come from a per-group instruction.
    var clearedGroupIDs: Set<String> {
        Set(overrides.filter(\.value.deleteEverything).map(\.key))
    }

    /// Candidates rebuilt from the revised decisions, plus the survivors of groups the user has
    /// asked to clear — those become deletable, which is the whole point of asking.
    private var revisedCandidates: [DeletionCandidate] {
        let revised = decisions
        var candidates = TierClassifier.candidates(
            decisions: revised,
            groups: result.groups,
            items: result.items
        )

        for decision in revised where clearedGroupIDs.contains(decision.id) {
            guard
                !candidates.contains(where: { $0.id == decision.keeperID }),
                let keeper = result.items[decision.keeperID],
                let tier = candidates.first(where: { $0.groupID == decision.id })?.tier
            else { continue }

            candidates.append(
                DeletionCandidate(
                    id: decision.keeperID,
                    groupID: decision.id,
                    keeperID: decision.keeperID,
                    tier: tier,
                    bytes: keeper.totalByteSize,
                    isPreSelected: false
                )
            )
        }
        return candidates
    }

    /// Candidates that still exist.
    var liveCandidates: [DeletionCandidate] {
        let source = overrides.isEmpty ? result.candidates : revisedCandidates
        return source.filter { !deletedIDs.contains($0.id) }
    }

    // MARK: - Derived

    var maxReclaimableBytes: Int64 { liveCandidates.reduce(Int64(0)) { $0 + $1.bytes } }

    var savings: SavingsBreakdown {
        SavingsCalculator.breakdown(for: selection.selectedIDs, items: result.items)
    }

    var violations: [CleanupViolation] {
        CleanupValidator.validate(
            selection: selection.selectedIDs,
            decisions: decisions,
            knownItemIDs: Set(result.items.keys),
            clearedGroupIDs: clearedGroupIDs
        )
    }

    var canDelete: Bool { !selection.isEmpty && violations.isEmpty && !isDeleting }

    var selectedCandidates: [DeletionCandidate] {
        liveCandidates.filter { selection.isSelected($0.id) }
    }

    /// The worst tier the current selection reaches into. What the confirmation has to lead
    /// with, because it is the only thing that determines whether this is reversible judgement
    /// or no loss at all.
    var deepestSelectedTier: RegretTier? {
        selectedCandidates.map(\.tier).max()
    }

    var judgementCallCount: Int {
        selectedCandidates.filter { !$0.tier.isLossless }.count
    }

    var budgetPlan: BudgetPlan {
        let allowed = Set(RegretTier.allCases.filter { $0 <= budgetDepth })
        return BudgetPlanner.plan(
            target: Int64(budgetBytes),
            candidates: liveCandidates,
            allowedTiers: allowed
        )
    }

    // MARK: - Selection

    func toggle(_ id: String) {
        selection.toggle(id)
    }

    func setSelected(_ isSelected: Bool, in section: ReviewSection) {
        selection.setSelected(isSelected, for: section.candidateIDs)
    }

    func setSelected(_ isSelected: Bool, in group: ReviewGroup) {
        selection.setSelected(isSelected, for: group.candidateIDs)
    }

    // MARK: - Overruling the engine

    /// Keeps `id` instead of whatever the scorer chose.
    ///
    /// In an exact group every member is interchangeable, so this is free. Anywhere else the
    /// members were each measured against the seed and against nothing else, so keeping a
    /// different copy leaves only the seed with direct evidence against it — the rest stop being
    /// offered rather than being re-parented to a survivor nobody compared them with.
    func chooseKeeper(_ id: String, inGroup groupID: String) {
        guard let decision = result.decisions.first(where: { $0.id == groupID }) else { return }
        guard GroupRevision.members(of: decision).contains(id) else { return }

        var override = overrides[groupID] ?? GroupOverride()
        override.keeperID = id == decision.keeperID ? nil : id
        // A group cannot be both "keep this one" and "delete all of it".
        override.deleteEverything = false
        overrides[groupID] = override.isEmpty ? nil : override

        pruneSelection()
    }

    /// What the user has chosen to keep in this group, which is the scored survivor until they
    /// say otherwise.
    func keeperID(inGroup groupID: String) -> String? {
        decisions.first(where: { $0.id == groupID })?.keeperID
    }

    /// Members no longer offered because the user kept something they were never compared with.
    func droppedMembers(inGroup groupID: String) -> [String] {
        guard
            let override = overrides[groupID],
            let decision = result.decisions.first(where: { $0.id == groupID })
        else { return [] }
        return GroupRevision.droppedMembers(override, of: decision)
    }

    func isClearingEverything(inGroup groupID: String) -> Bool {
        overrides[groupID]?.deleteEverything ?? false
    }

    /// Deletes every copy in a group, survivor included.
    ///
    /// Deliberately awkward to reach and impossible to arrive at by accident: no pre-selection,
    /// no budget plan and no "select all" can turn this on, and it is the only thing in the app
    /// that may leave a group with nothing.
    func setClearingEverything(_ isClearing: Bool, inGroup groupID: String) {
        guard let decision = result.decisions.first(where: { $0.id == groupID }) else { return }

        var override = overrides[groupID] ?? GroupOverride()
        override.deleteEverything = isClearing
        overrides[groupID] = override.isEmpty ? nil : override

        let members = GroupRevision.members(of: GroupRevision.apply(override, to: decision))
        if isClearing {
            selection.setSelected(true, for: members)
        } else {
            selection.setSelected(false, for: [decisions.first(where: { $0.id == groupID })?.keeperID].compactMap { $0 })
        }
        pruneSelection()
    }

    /// Drops ticks for anything that is no longer on offer, so a selection can never outlive the
    /// decision that justified it.
    private func pruneSelection() {
        let offered = Set(liveCandidates.map(\.id))
        let stale = selection.selectedIDs.subtracting(offered)
        if !stale.isEmpty {
            selection.setSelected(false, for: Array(stale))
        }
    }

    func applyBudgetPlan() {
        selection.replace(with: budgetPlan.selectedIDs)
    }

    func resetToSafeDefaults() {
        selection = .preSelected(from: liveCandidates)
    }

    // MARK: - Deletion

    func delete() async {
        guard canDelete else { return }

        let ids = selection.selectedIDs.sorted()

        // Re-checked here rather than trusted from the button's disabled state: this is the
        // last point before the library is told to destroy something, and the selection has
        // passed through UI state to get here.
        let blocking = CleanupValidator.validate(
            selection: Set(ids),
            decisions: decisions,
            knownItemIDs: Set(result.items.keys),
            clearedGroupIDs: clearedGroupIDs
        )
        guard blocking.isEmpty else {
            failure = DeletionError.unsafeSelection(blocking.map(\.description)).localizedDescription
            return
        }

        isDeleting = true
        failure = nil

        // Captured before the selection is cleared: the receipt describes what was sent,
        // not what is left.
        let sentSavings = SavingsCalculator.breakdown(for: Set(ids), items: result.items)

        // What each file looked like when it was scanned. The deleter refuses anything that no
        // longer matches, because a file can be replaced between the scan and the tap and
        // nothing in its identifier would say so.
        let stamps = ids.reduce(into: [String: FileStamp]()) { stamps, id in
            guard let item = result.items[id], item.source == .fileFolder else { return }
            stamps[id] = FileStamp(item)
        }

        do {
            let completed = try await deleter.delete(ids: ids, expecting: stamps)
            outcome = completed
            deletedIDs.formUnion(completed.deletedIDs)
            selection.clear()

            if !completed.deletedIDs.isEmpty {
                history?.record(
                    deletion: HistoryBuilder.deletionRecord(
                        deletedIDs: completed.deletedIDs,
                        result: result,
                        savings: sentSavings,
                        performedAt: Date(),
                        candidates: liveCandidates
                    )
                )
            }
        } catch {
            failure = error.localizedDescription
        }

        isDeleting = false
    }
}
