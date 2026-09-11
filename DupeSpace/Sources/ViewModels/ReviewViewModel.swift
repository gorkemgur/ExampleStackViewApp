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

    let result: ScanResult
    let sections: [ReviewSection]

    private let deleter: MediaDeleting

    init(result: ScanResult, deleter: MediaDeleting) {
        self.result = result
        self.deleter = deleter
        self.sections = ReviewBuilder.sections(for: result)
        self.selection = .preSelected(from: result.candidates)
    }

    // MARK: - Derived

    var maxReclaimableBytes: Int64 { result.reclaimableBytes }

    var savings: SavingsBreakdown {
        SavingsCalculator.breakdown(for: selection.selectedIDs, items: result.items)
    }

    var violations: [CleanupViolation] {
        CleanupValidator.validate(
            selection: selection.selectedIDs,
            decisions: result.decisions,
            knownItemIDs: Set(result.items.keys)
        )
    }

    var canDelete: Bool { !selection.isEmpty && violations.isEmpty && !isDeleting }

    var selectedCandidates: [DeletionCandidate] {
        result.candidates.filter { selection.isSelected($0.id) }
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
            candidates: result.candidates,
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

    func applyBudgetPlan() {
        selection.replace(with: budgetPlan.selectedIDs)
    }

    func resetToSafeDefaults() {
        selection = .preSelected(from: result.candidates)
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
            decisions: result.decisions,
            knownItemIDs: Set(result.items.keys)
        )
        guard blocking.isEmpty else {
            failure = DeletionError.unsafeSelection(blocking.map(\.description)).localizedDescription
            return
        }

        isDeleting = true
        failure = nil

        do {
            outcome = try await deleter.delete(ids: ids)
            selection.clear()
        } catch {
            failure = error.localizedDescription
        }

        isDeleting = false
    }
}
