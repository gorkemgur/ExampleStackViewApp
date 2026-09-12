import Combine
import Foundation
import DupeCore

@MainActor
final class ReviewViewModel: ObservableObject {

    @Published private(set) var selection: CleanupSelection {
        didSet {
            cachedViolations = nil
            cachedSavings = nil
            cachedSelectedCandidates = nil
        }
    }
    @Published private(set) var isDeleting = false
    /// How far the deletion has got, as the deleter reports it.
    ///
    /// Not a number the screen invents. The photo half is one atomic change behind the system's
    /// own confirmation, so it carries `isDeterminate == false` and whatever draws it has to
    /// say "working" rather than "sixty per cent".
    @Published private(set) var deletionProgress: DeletionProgress?
    @Published private(set) var outcome: DeletionOutcome?
    /// What actually went, measured from `outcome.deletedIDs` rather than from what was asked
    /// for. The two differ whenever a file was refused or had already gone, and the success
    /// figure has to be the smaller, true one.
    @Published private(set) var outcomeSavings: SavingsBreakdown?

    /// Identifies the deletion currently in flight.
    ///
    /// The deleter reports from a detached task, so each update reaches the main actor through
    /// an unstructured `Task`, and those are unordered: one could still be queued when
    /// `delete()` has already returned and cleared the progress, leaving a finished deletion
    /// wearing a live progress state. An update that does not carry the current run's token is
    /// a straggler and is dropped.
    private var deletionRun = 0
    @Published private(set) var failure: String?

    /// Target for the "I need this much back" slider, in bytes.
    @Published var budgetBytes: Double = 0 {
        didSet { cachedBudgetPlan = nil }
    }
    /// How far the slider is allowed to reach. Starts at the tiers that cost the user nothing.
    @Published var budgetDepth: RegretTier = .inferiorCopy {
        didSet { cachedBudgetPlan = nil }
    }

    /// Items that have actually been removed. Kept so the list stops offering copies that no
    /// longer exist the moment a deletion succeeds, rather than leaving the user staring at
    /// rows that would fail if tapped.
    @Published private(set) var deletedIDs: Set<String> = [] {
        didSet { invalidateDerived() }
    }

    /// Show only one kind of thing, or everything.
    ///
    /// A filter, deliberately, and not a second level of section. The axis this app files
    /// things under is what deleting them costs — that is the product's whole idea and the
    /// safety model is defined on it — so splitting every tier into photos, videos and files
    /// would double the headings and bury the decision under navigation. But "just show me the
    /// videos" is a real thing to want, because videos are where the bytes are, and until now
    /// there was no way to ask it.
    @Published var kindFilter: MediaKind? {
        didSet {
            cachedVisibleSections = nil
            cachedKindSections = nil
            // The plan is made from what is on screen, so changing what is on screen changes
            // the plan — and the fader's ceiling with it.
            cachedPlannable = nil
            cachedBudgetPlan = nil
            clampBudget()
        }
    }

    /// Where the user has overruled the engine: a different survivor, or a group they want gone
    /// entirely. Keyed by group id.
    @Published private(set) var overrides: [String: GroupOverride] = [:] {
        didSet { invalidateDerived() }
    }

    /// What the last export wrote, if the user asked for one before deleting.
    ///
    /// `docs/CONCEPT.md` has promised this since the first day of the project and nothing
    /// implemented it: the original bytes of everything about to be deleted, written to a
    /// folder the user picks, with a manifest beside them naming the copy that stayed. It is
    /// the difference between "Recently Deleted holds this for thirty days" and a decision that
    /// is recoverable at all — for files outside the photo library there is no thirty days.
    @Published private(set) var exportReceipt: ExportReceipt?
    @Published private(set) var isExporting = false
    @Published private(set) var exportFailure: String?

    let result: ScanResult

    private let allSections: [ReviewSection]
    private let deleter: MediaDeleting
    private let exporter: any OriginalExporting
    private weak var history: (any HistoryRecording)?

    /// Every id the scan knows about. Hoisted out of `violations`, which is read through
    /// `canDelete` five times in one pass of the review screen's body and twice more in the
    /// confirmation — so a fifty-thousand-item library was allocating a fifty-thousand-element
    /// set seven times per frame, while a finger was on the slider. It cannot change: `result`
    /// is a `let`.
    private let knownItemIDs: Set<String>

    // Everything below is derived from `result`, `overrides` and `deletedIDs`, none of which
    // move while a checkbox is being ticked. They used to be recomputed from scratch on every
    // read, and SwiftUI reads them several times per body evaluation, so one tap re-ran the
    // whole revision — decisions, candidates, tier classification, three nested sorts — a
    // dozen times over. Cleared by `invalidateDerived()` when the things they are derived from
    // actually change.
    private var cachedDecisions: [GroupDecision]?
    private var cachedRevisedCandidates: [DeletionCandidate]?
    private var cachedLiveCandidates: [DeletionCandidate]?
    private var cachedSections: [ReviewSection]?
    private var cachedSafeDefault: CleanupSelection?
    private var cachedViolations: [CleanupViolation]?
    // Read several times per body pass, and every frame of a fader drag: `budgetPlan` is a
    // filter and a sort through every live candidate, `savings` walks every selected id, and
    // `selectedCandidates` is a full pass that `deepestSelectedTier` and `judgementCallCount`
    // each walk again.
    private var cachedBudgetPlan: BudgetPlan?
    private var cachedSavings: SavingsBreakdown?
    private var cachedSelectedCandidates: [DeletionCandidate]?
    private var cachedVisibleSections: [ReviewSection]?
    private var cachedKindSections: [KindSection]?
    private var cachedPlannable: [DeletionCandidate]?
    private var cachedVetoed: Set<String>?

    init(
        result: ScanResult,
        deleter: MediaDeleting,
        history: (any HistoryRecording)? = nil,
        exporter: any OriginalExporting = StubOriginalExporter()
    ) {
        self.result = result
        self.deleter = deleter
        self.history = history
        self.exporter = exporter
        self.allSections = ReviewBuilder.sections(for: result)
        self.knownItemIDs = Set(result.items.keys)
        self.selection = .preSelected(from: result.candidates)

        // The slider opens where the app's own suggestion already sits. Starting at zero made
        // the card say "nothing is selected by a plan of zero" directly above a bar saying
        // three things were selected — the screen contradicting itself on first sight.
        budgetBytes = Double(
            result.candidates.filter(\.isPreSelected).reduce(Int64(0)) { $0 + $1.bytes }
        )
    }

    /// Drops every cached derivation. Called whenever an override or a deletion lands, which
    /// are the only two things any of them depend on.
    private func invalidateDerived() {
        cachedDecisions = nil
        cachedRevisedCandidates = nil
        cachedLiveCandidates = nil
        cachedSections = nil
        cachedSafeDefault = nil
        cachedViolations = nil
        cachedBudgetPlan = nil
        cachedSavings = nil
        cachedSelectedCandidates = nil
        cachedVisibleSections = nil
        cachedKindSections = nil
        cachedPlannable = nil
        cachedVetoed = nil
    }

    var sections: [ReviewSection] {
        if let cachedSections { return cachedSections }
        let value: [ReviewSection]
        if overrides.isEmpty {
            value = allSections.compactMap { $0.removing(deletedIDs) }
        } else {
            value = ReviewBuilder
                .sections(candidates: revisedCandidates, items: result.items)
                .compactMap { $0.removing(deletedIDs) }
        }
        cachedSections = value
        return value
    }

    /// The sections as the list shows them, which is `sections` narrowed to one kind.
    ///
    /// Kept separate from `sections` on purpose: `sections` is what the scan found and never
    /// moves, and the chip row's own tallies are read off it. What the fader and the plan work
    /// on is this — because a control that ticks copies the list is not showing is a control
    /// that deletes things the user never saw.
    var visibleSections: [ReviewSection] {
        if let cachedVisibleSections { return cachedVisibleSections }
        let value: [ReviewSection]
        if let kindFilter {
            value = sections.compactMap { section in
                let groups = section.groups.filter { $0.keeper.kind == kindFilter }
                return groups.isEmpty ? nil : ReviewSection(tier: section.tier, groups: groups)
            }
        } else {
            value = sections
        }
        cachedVisibleSections = value
        return value
    }

    /// One kind of thing, with its own tier rungs inside it.
    struct KindSection: Identifiable {
        let kind: MediaKind
        let sections: [ReviewSection]

        var id: Int { kind.rawValue }
        var bytes: Int64 { sections.reduce(Int64(0)) { $0 + $1.bytes } }
        var groupCount: Int { sections.reduce(0) { $0 + $1.groups.count } }
        var itemCount: Int { sections.reduce(0) { $0 + $1.itemCount } }
    }

    /// The list as two levels: what kind of thing, then what deleting it costs.
    ///
    /// Kind is the outer level because it is the question people arrive with — "how much of
    /// this is video" — and because the two axes are independent: a video can be an identical
    /// copy or a merely similar one, exactly as a photo can. Cost stays the inner level,
    /// because that is what the decision is made on and what the safety model is defined in
    /// terms of; it is not being demoted, it is being nested under the coarser question.
    ///
    /// Biggest kind first. On a phone the answer is almost always video, and the point of
    /// opening this screen is to find the space.
    var kindSections: [KindSection] {
        if let cachedKindSections { return cachedKindSections }

        let value = availableKinds
            .filter { kindFilter == nil || kindFilter == $0 }
            .map { kind in
                KindSection(
                    kind: kind,
                    sections: sections.compactMap { section in
                        let groups = section.groups.filter { $0.keeper.kind == kind }
                        return groups.isEmpty ? nil : ReviewSection(tier: section.tier, groups: groups)
                    }
                )
            }
            .filter { !$0.sections.isEmpty }
            .sorted { $0.bytes > $1.bytes }

        cachedKindSections = value
        return value
    }

    /// The kinds this scan actually turned up. A section or a filter offering "Videos" on a
    /// library with none is a control that can only disappoint.
    var availableKinds: [MediaKind] {
        let present = Set(sections.flatMap { $0.groups.map { $0.keeper.kind } })
        return [.image, .video, .document].filter(present.contains)
    }

    /// What one kind is worth, for the filter's own label.
    func tally(for kind: MediaKind?) -> (items: Int, bytes: Int64) {
        let groups = sections.flatMap(\.groups).filter { kind == nil || $0.keeper.kind == kind }
        return (
            groups.reduce(0) { $0 + $1.candidates.count },
            groups.reduce(Int64(0)) { $0 + $1.bytes }
        )
    }

    /// The decisions as they stand after the user has overruled any of them.
    var decisions: [GroupDecision] {
        if let cachedDecisions { return cachedDecisions }
        let value = GroupRevision.apply(overrides, to: result.decisions)
        cachedDecisions = value
        return value
    }

    /// Groups the user has explicitly asked to remove entirely. The only thing that may empty a
    /// group, and it can only come from a per-group instruction.
    var clearedGroupIDs: Set<String> {
        Set(overrides.filter(\.value.deleteEverything).map(\.key))
    }

    /// Candidates rebuilt from the revised decisions, plus the survivors of groups the user has
    /// asked to clear — those become deletable, which is the whole point of asking.
    private var revisedCandidates: [DeletionCandidate] {
        if let cachedRevisedCandidates { return cachedRevisedCandidates }
        let value = buildRevisedCandidates()
        cachedRevisedCandidates = value
        return value
    }

    private func buildRevisedCandidates() -> [DeletionCandidate] {
        let revised = decisions
        var candidates = TierClassifier.candidates(
            decisions: revised,
            groups: result.groups,
            items: result.items
        )

        for decision in revised where clearedGroupIDs.contains(decision.id) {
            guard
                !candidates.contains(where: { $0.id == decision.keeperID }),
                let keeper = result.items[decision.keeperID]
            else { continue }

            // `.similar`, and never the group's own tier.
            //
            // This used to take the tier of the first candidate in the group, and
            // `TierClassifier` emits them cheapest-first — so the survivor, the one copy whose
            // deletion destroys the photograph itself, was filed under "identical copies,
            // deleting these loses nothing at all". The confirmation sheet then read "from 3
            // items that cost you nothing" over a group that was about to cease to exist, and
            // `judgementCallCount` was zero so the warning card never drew. Being the last copy
            // is the most expensive thing a deletion can be; it takes the dearest rung.
            candidates.append(
                DeletionCandidate(
                    id: decision.keeperID,
                    groupID: decision.id,
                    keeperID: decision.keeperID,
                    tier: .similar,
                    bytes: keeper.totalByteSize,
                    isPreSelected: false,
                    // And no bulk control may ever reach it. The only thing allowed to select
                    // this is the deliberately awkward control on the group's own screen, which
                    // is what put it here.
                    requiresHuman: true
                )
            )
        }
        return candidates
    }

    /// Candidates that still exist.
    var liveCandidates: [DeletionCandidate] {
        if let cachedLiveCandidates { return cachedLiveCandidates }
        let source = overrides.isEmpty ? result.candidates : revisedCandidates
        let value = source.filter { !deletedIDs.contains($0.id) }
        cachedLiveCandidates = value
        return value
    }

    /// What the app would tick if the user had not touched anything. Cached because
    /// `hasChangedTheProposal` is read on every toolbar pass.
    private var safeDefaultSelection: CleanupSelection {
        if let cachedSafeDefault { return cachedSafeDefault }
        let value = CleanupSelection.preSelected(from: liveCandidates)
        cachedSafeDefault = value
        return value
    }

    // MARK: - Derived

    var maxReclaimableBytes: Int64 { liveCandidates.reduce(Int64(0)) { $0 + $1.bytes } }

    /// True once there is nothing left to offer — everything found has been dealt with.
    var isFinished: Bool { liveCandidates.isEmpty }

    var savings: SavingsBreakdown {
        if let cachedSavings { return cachedSavings }
        let value = SavingsCalculator.breakdown(for: selection.selectedIDs, items: result.items)
        cachedSavings = value
        return value
    }

    var violations: [CleanupViolation] {
        if let cachedViolations { return cachedViolations }
        let value = CleanupValidator.validate(
            selection: selection.selectedIDs,
            decisions: decisions,
            knownItemIDs: knownItemIDs,
            clearedGroupIDs: clearedGroupIDs
        )
        cachedViolations = value
        return value
    }

    var canDelete: Bool { !selection.isEmpty && violations.isEmpty && !isDeleting }

    var selectedCandidates: [DeletionCandidate] {
        if let cachedSelectedCandidates { return cachedSelectedCandidates }
        let value = liveCandidates.filter { selection.isSelected($0.id) }
        cachedSelectedCandidates = value
        return value
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

    /// What a plan is allowed to tick: everything still on offer, narrowed to the kind the
    /// list is currently showing.
    ///
    /// It used to be every live candidate regardless of the filter. Filter to Videos, drag the
    /// fader to 4 GB, tap the key — and the dock said ninety items selected on a screen showing
    /// twenty, because the rest were photo groups the filter was hiding. On a screen whose one
    /// job is deciding what gets deleted, no control may select something it is not showing.
    var plannableCandidates: [DeletionCandidate] {
        if let cachedPlannable { return cachedPlannable }
        let value: [DeletionCandidate]
        if kindFilter == nil {
            value = liveCandidates
        } else {
            let onScreen = Set(visibleSections.flatMap(\.candidateIDs))
            value = liveCandidates.filter { onScreen.contains($0.id) }
        }
        cachedPlannable = value
        return value
    }

    /// The fader's ceiling: what a plan could take at most, which is what is plannable rather
    /// than what the whole scan found.
    var plannableBytes: Int64 { plannableCandidates.reduce(Int64(0)) { $0 + $1.bytes } }

    var budgetPlan: BudgetPlan {
        if let cachedBudgetPlan { return cachedBudgetPlan }
        let allowed = Set(RegretTier.allCases.filter { $0 <= budgetDepth })
        let value = BudgetPlanner.plan(
            target: Int64(budgetBytes),
            candidates: plannableCandidates,
            allowedTiers: allowed
        )
        cachedBudgetPlan = value
        return value
    }

    // MARK: - Selection

    func toggle(_ id: String) {
        selection.toggle(id)
    }

    /// A whole tier at once — minus the copies no bulk control may touch.
    ///
    /// This acts across every group in a rung, most of which the user has not opened. Ticking a
    /// favourite, an album member, or the last copy on the device because its survivor is in
    /// iCloud is exactly what `requiresHuman` exists to prevent, and "Select all" is as much a
    /// bulk control as the budget key is. Deselecting is unrestricted: taking something *out*
    /// of a deletion never needs a guard.
    func setSelected(_ isSelected: Bool, in section: ReviewSection) {
        guard isSelected else {
            selection.setSelected(false, for: section.candidateIDs)
            return
        }
        selection.setSelected(true, for: bulkSelectableIDs(in: section))
    }

    /// What a section-wide control is allowed to tick.
    func bulkSelectableIDs(in section: ReviewSection) -> [String] {
        let vetoed = vetoedIDs
        return section.candidateIDs.filter { !vetoed.contains($0) }
    }

    /// How many copies in this rung the app will not tick for you.
    ///
    /// Said on screen, because a "Select all" that quietly leaves things behind is worse than
    /// one that refuses: the user reads the count in the dock, finds it lower than the rung's
    /// own figure, and has no way to learn why.
    func needsEyesCount(in section: ReviewSection) -> Int {
        section.candidateIDs.count - bulkSelectableIDs(in: section).count
    }

    /// Every candidate a bulk control must leave alone, by id.
    private var vetoedIDs: Set<String> {
        if let cachedVetoed { return cachedVetoed }
        let value = Set(liveCandidates.filter(\.requiresHuman).map(\.id))
        cachedVetoed = value
        return value
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
        clampBudget()
        clearFilterIfItHasNothingLeft()
    }

    /// Drops a filter whose kind no longer exists.
    ///
    /// Filter to Videos, delete the twenty videos, and the chip row disappeared — it only drew
    /// when more than one kind was live — while `kindFilter` stayed `.video`. The result was an
    /// empty screen saying "nothing of that kind" over a hundred and fifty hidden photo groups,
    /// with no control anywhere on it to undo the filter.
    private func clearFilterIfItHasNothingLeft() {
        guard let kindFilter, !availableKinds.contains(kindFilter) else { return }
        self.kindFilter = nil
    }

    /// Pulls the target back inside what is actually still on offer.
    ///
    /// The slider's range is `0...maxReclaimableBytes`, so the user can never drag past the
    /// ceiling — but the ceiling moves. Delete 2 GB and the value the user set against the old
    /// ceiling survives, so the card read "I NEED 2.02 GB BACK" with the handle pinned to the
    /// far end of a track whose end was now 12.3 MB, under a plan that could only ever select
    /// everything. The number has to follow the ceiling down.
    private func clampBudget() {
        let ceiling = Double(plannableBytes)
        if budgetBytes > ceiling {
            budgetBytes = ceiling
        }
    }

    // MARK: - Keeping a copy first

    /// What an export would write: every selected copy, in the order the list offers them,
    /// each with the manifest row that names what it was and what stays in its place.
    var exportPlan: [(item: MediaItem, entry: ExportManifest.Entry)] {
        ExportManifestBuilder.entries(for: selectedCandidates, items: result.items)
    }

    /// True once every selected copy has been written out. Re-ticking something after an export
    /// invalidates it, because the receipt no longer covers the selection.
    var exportCoversSelection: Bool {
        guard let exportReceipt else { return false }
        let written = Set(exportReceipt.exportedIDs)
        return !selection.isEmpty && selection.selectedIDs.allSatisfy(written.contains)
    }

    func exportOriginals(to destination: URL) async {
        guard !isExporting, !selection.isEmpty else { return }
        isExporting = true
        exportFailure = nil

        let plan = exportPlan
        do {
            exportReceipt = try await exporter.export(plan, to: destination)
        } catch {
            exportReceipt = nil
            exportFailure = error.localizedDescription
        }
        isExporting = false
    }

    func clearExportFailure() {
        exportFailure = nil
    }

    func applyBudgetPlan() {
        selection.replace(with: budgetPlan.selectedIDs)
    }

    /// Back to what the app would have suggested: every override dropped, and only the copies
    /// it is willing to vouch for ticked.
    ///
    /// A screen that lets you overrule it needs a way back, or the choice is a trap rather than
    /// a choice.
    func resetToSafeDefaults() {
        overrides = [:]
        selection = safeDefaultSelection
        clampBudget()
    }

    /// True once the user has changed anything the app proposed.
    var hasChangedTheProposal: Bool {
        !overrides.isEmpty || selection != safeDefaultSelection
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
            knownItemIDs: knownItemIDs,
            clearedGroupIDs: clearedGroupIDs
        )
        guard blocking.isEmpty else {
            failure = DeletionError.unsafeSelection(blocking.map(\.description)).localizedDescription
            return
        }

        isDeleting = true
        failure = nil
        deletionRun &+= 1
        let run = deletionRun
        deletionProgress = .starting(total: ids.count, isDeterminate: false, stage: .photoLibrary)

        // Captured before the selection is cleared: the receipt describes what was sent,
        // not what is left. The candidate list has to be captured here too — `liveCandidates`
        // excludes everything already deleted, and by the time the receipt is written that is
        // exactly the items it needs to describe. Reading it afterwards left every line with no
        // candidate to look up: no keeper name, and a tier defaulting to the riskiest one, so a
        // receipt for three identical copies claimed three judgement calls.
        let sentSavings = SavingsCalculator.breakdown(for: Set(ids), items: result.items)
        let sentCandidates = liveCandidates

        // What each file looked like when it was scanned. The deleter refuses anything that no
        // longer matches, because a file can be replaced between the scan and the tap and
        // nothing in its identifier would say so.
        let stamps = ids.reduce(into: [String: FileStamp]()) { stamps, id in
            guard let item = result.items[id], item.source == .fileFolder else { return }
            stamps[id] = FileStamp(item)
        }

        do {
            let completed = try await deleter.delete(ids: ids, expecting: stamps) { [weak self] step in
                // The deleter reports from whichever thread it is running on — the file half
                // runs on a detached task — so the hop is here rather than at every call site.
                Task { @MainActor in
                    guard let self, self.deletionRun == run else { return }
                    self.deletionProgress = step
                }
            }
            outcome = completed
            // Measured from what came back, not from what was sent.
            outcomeSavings = SavingsCalculator.breakdown(for: Set(completed.deletedIDs), items: result.items)
            deletedIDs.formUnion(completed.deletedIDs)
            selection.clear()
            clampBudget()
            clearFilterIfItHasNothingLeft()

            // A deletion that spans both sources can half-succeed. The outcome says so rather
            // than throwing, so the receipt below is still written for what actually went and
            // the user still sees what did not.
            failure = completed.failure

            if !completed.deletedIDs.isEmpty {
                history?.record(
                    deletion: HistoryBuilder.deletionRecord(
                        deletedIDs: completed.deletedIDs,
                        result: result,
                        savings: sentSavings,
                        performedAt: Date(),
                        candidates: sentCandidates
                    )
                )
            }
        } catch {
            failure = error.localizedDescription
        }

        deletionProgress = nil
        isDeleting = false
    }
}
