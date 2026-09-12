import SwiftUI
import DupeCore

struct ReviewView: View {

    @StateObject private var model: ReviewViewModel
    @State private var showingConfirm = false

    private let loader: any ThumbnailLoading

    init(result: ScanResult, history: HistoryViewModel) {
        _model = StateObject(
            wrappedValue: ReviewViewModel(
                result: result,
                deleter: AppEnvironment.makeDeleter(),
                history: history
            )
        )
        loader = AppEnvironment.makeThumbnailLoader()
    }

    var body: some View {
        List {
            if let outcome = model.outcome {
                outcomeSection(outcome)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let failure = model.failure, model.outcome == nil {
                Section {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("review.failure")
                }
            }

            budgetSection

            ForEach(model.sections) { section in
                sectionView(section)
            }
        }
        .listStyle(.insetGrouped)
        .animation(.snappy(duration: 0.32), value: model.selection)
        .animation(.snappy(duration: 0.35), value: model.deletedIDs)
        .sensoryFeedback(.selection, trigger: model.selection.count)
        .sensoryFeedback(.success, trigger: model.outcome != nil)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            deleteBar
        }
        .sheet(isPresented: $showingConfirm) {
            ConfirmDeleteSheet(model: model)
        }
    }

    // MARK: - Budget

    private var budgetSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("I need")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ByteFormatting.string(Int64(model.budgetBytes)))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("budget.target")
                    Text("back")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $model.budgetBytes,
                    in: 0...Double(max(model.maxReclaimableBytes, 1))
                )
                .accessibilityIdentifier("budget.slider")

                Picker("How far to go", selection: $model.budgetDepth) {
                    Text("No loss").tag(RegretTier.inferiorCopy)
                    Text("+ bursts").tag(RegretTier.burstLeftover)
                    Text("+ similar").tag(RegretTier.similar)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("budget.depth")

                Text(planSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("budget.summary")

                Button("Select this plan") {
                    model.applyBudgetPlan()
                }
                .buttonStyle(.bordered)
                .disabled(model.budgetPlan.selected.isEmpty)
                .accessibilityIdentifier("budget.apply")
            }
            .padding(.vertical, 6)
        } header: {
            Text("Space budget")
        } footer: {
            Text("Starts with the copies that cost you nothing and only reaches further if you let it.")
        }
    }

    private var planSummary: String {
        let plan = model.budgetPlan
        guard !plan.selected.isEmpty else {
            return "Drag to set a target. Nothing is selected by a plan of zero."
        }
        let reached = ByteFormatting.string(plan.reclaimedBytes)
        let deepest = plan.deepestTier.map { ScanCopy.title(for: $0).lowercased() } ?? "nothing"
        if plan.meetsTarget {
            return "\(Counting.items(plan.selected.count)), \(reached) — reaching as far as \(deepest)."
        }
        return "Only \(reached) is available at this setting (\(Counting.items(plan.selected.count))). Allow more, or accept less."
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionView(_ section: ReviewSection) -> some View {
        Section {
            ForEach(section.groups) { group in
                NavigationLink {
                    GroupDetailView(group: group, model: model, loader: loader)
                } label: {
                    GroupRowView(
                        group: group,
                        selectedCount: group.candidateIDs.filter { model.selection.isSelected($0) }.count,
                        loader: loader
                    )
                }
            }
        } header: {
            HStack {
                Text(ScanCopy.title(for: section.tier))
                    .accessibilityIdentifier("review.section.\(section.tier.rawValue)")
                Spacer()
                // "None"/"All" read as labels for the current state rather than as the action
                // they perform, which is the wrong ambiguity on a screen that deletes things.
                Button(model.selection.containsAll(section.candidateIDs) ? "Deselect all" : "Select all") {
                    model.setSelected(!model.selection.containsAll(section.candidateIDs), in: section)
                }
                .font(.caption.weight(.semibold))
                .textCase(nil)
                .accessibilityIdentifier("review.selectall.\(section.tier.rawValue)")
            }
        } footer: {
            Text("\(ScanCopy.subtitle(for: section.tier)) · \(ByteFormatting.string(section.bytes)) across \(Counting.items(section.itemCount))")
        }
    }

    // MARK: - Bottom bar

    private var deleteBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteFormatting.string(model.savings.onDeviceBytes))
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("review.total")
                Text("\(model.selection.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("review.count")
            }

            Spacer(minLength: 0)

            Button("Delete…") {
                showingConfirm = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!model.canDelete)
            .accessibilityIdentifier("review.delete")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Outcome

    @ViewBuilder
    private func outcomeSection(_ outcome: DeletionOutcome) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(Counting.items(outcome.deletedCount)) removed", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: outcome.deletedCount)
                    .accessibilityIdentifier("review.result")

                Text("The receipt is in History: what went, and what was kept in its place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("They are in Recently Deleted for 30 days. Empty that album in Photos to get the space back now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if outcome.missingCount > 0 {
                    Text("\(Counting.items(outcome.missingCount)) \(outcome.missingCount == 1 ? "was" : "were") already gone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
