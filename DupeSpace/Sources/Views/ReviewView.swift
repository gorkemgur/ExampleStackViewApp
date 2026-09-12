import SwiftUI
import DupeCore

/// The regret ladder, drawn as one.
///
/// This was an inset-grouped `List` whose only statement of the ordering was a section header,
/// which meant the spine of the product — cheapest first, dearest last — was a piece of
/// typography rather than a piece of layout. It is now a rail: one line running down the screen,
/// a node at each rung, and the rung's colour carried on everything that belongs to it, so
/// "these cost you nothing and those are your call" is visible before a word is read.
struct ReviewView: View {

    @StateObject private var model: ReviewViewModel
    @State private var showingConfirm = false
    @State private var confirmingReset = false

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let outcome = model.outcome {
                    outcomeSection(outcome)
                }

                if let failure = model.failure, model.outcome == nil {
                    Card("Nothing was deleted", symbolName: "exclamationmark.triangle", identifier: "review.failure.title", rail: DS.tier(.similar)) {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("review.failure")
                    }
                }

                if model.isFinished {
                    finishedSection
                } else {
                    budgetSection
                }

                ladder
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(DS.ink, ignoresSafeAreaEdges: .all)
        .sensoryFeedback(.selection, trigger: model.selection.count)
        .sensoryFeedback(.success, trigger: model.outcome != nil)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.hasChangedTheProposal {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") { confirmingReset = true }
                        .accessibilityIdentifier("review.reset")
                }
            }
        }
        .confirmationDialog(
            "Go back to what the app suggested?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset my choices", role: .destructive) {
                withAnimation(Motion.content) { model.resetToSafeDefaults() }
            }
            Button("Keep my choices", role: .cancel) {}
        } message: {
            Text("This drops every copy you chose to keep instead, and re-ticks only what deleting provably costs nothing. Nothing has been deleted either way.")
        }
        .safeAreaInset(edge: .bottom) {
            reclaimBar
        }
        // After the inset, not before: the bottom bar is where the selection total actually
        // changes, and an animation applied above it never reaches it.
        .animation(Motion.content, value: model.selection)
        .animation(Motion.content, value: model.deletedIDs)
        .sheet(isPresented: $showingConfirm) {
            ConfirmDeleteSheet(model: model)
        }
    }

    // MARK: - Budget

    /// After the last candidate is gone the budget card was still on screen saying "I need
    /// 2.02 GB back" above "nothing is selected by a plan of zero" — the screen arguing with
    /// itself over a question that no longer has an answer.
    private var finishedSection: some View {
        Card(
            "Nothing left to review",
            symbolName: "checkmark.seal",
            identifier: "review.finished",
            rail: DS.aqua
        ) {
            Text("Everything this scan found has been dealt with. Scan again when the library has changed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The one control that makes this app what it is, so it gets the instrument panel: a dark
    /// slab, the target set as a gauge reading, and the reach of the current setting drawn as a
    /// ramp in the ladder's own colours underneath the slider that moves it.
    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("I need", tint: DS.brandBottom)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Readout.bytes(Int64(model.budgetBytes), tint: DS.brandBottom)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("budget.target")

                    Text("back")
                        .font(.subheadline)
                        .foregroundStyle(DS.onSlab.opacity(0.6))

                    Spacer(minLength: 0)
                }
            }

            Slider(
                value: $model.budgetBytes,
                in: 0...Double(max(model.maxReclaimableBytes, 1))
            )
            .tint(DS.brandBottom)
            .accessibilityIdentifier("budget.slider")

            reachRamp

            Picker("How far to go", selection: $model.budgetDepth) {
                Text("No loss").tag(RegretTier.inferiorCopy)
                Text("+ bursts").tag(RegretTier.burstLeftover)
                Text("+ similar").tag(RegretTier.similar)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("budget.depth")

            Text(planSummary)
                .font(.caption)
                .foregroundStyle(DS.onSlab.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("budget.summary")

            Button("Select this plan") {
                model.applyBudgetPlan()
            }
            .buttonStyle(.key)
            .disabled(model.budgetPlan.selected.isEmpty)
            .accessibilityIdentifier("budget.apply")

            Text("Starts with the copies that cost you nothing and only reaches further if you let it.")
                .font(.caption2)
                .foregroundStyle(DS.onSlab.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(DS.slab)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    /// What each rung of the ladder is worth, and how far the current setting is allowed to
    /// reach into it. Muted segments are real space the plan will not touch at this depth.
    private var reachRamp: some View {
        let rungs = model.sections.map { (tier: $0.tier, bytes: Double($0.bytes)) }
        let total = max(rungs.reduce(0) { $0 + $1.bytes }, 1)

        return MeterTrack(
            segments: rungs.map { rung in
                MeterTrack.Segment(
                    id: "reach.\(rung.tier.rawValue)",
                    value: rung.bytes,
                    color: DS.tierVivid(rung.tier),
                    isMuted: rung.tier > model.budgetDepth
                )
            },
            total: total,
            height: 7
        )
        .animation(Motion.control, value: model.budgetDepth)
        .accessibilityHidden(true)
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

    // MARK: - The ladder

    private var ladder: some View {
        let sections = model.sections
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                rung(section, isLast: index == sections.count - 1)
            }
        }
    }

    private func rung(_ section: ReviewSection, isLast: Bool) -> some View {
        let tint = DS.tier(section.tier)

        return HStack(alignment: .top, spacing: 14) {
            rail(tint: tint, isLast: isLast)

            VStack(alignment: .leading, spacing: 12) {
                rungHeader(section, tint: tint)

                VStack(spacing: 8) {
                    ForEach(section.groups) { group in
                        groupRow(group, tint: tint)
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 26)
        }
    }

    /// The line the whole screen hangs off. Its node is the rung; it fades out under the last
    /// one rather than stopping dead, because the ladder ends where the offers end.
    private func rail(tint: Color, isLast: Bool) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(tint)
                .frame(width: 11, height: 11)
                .padding(.top, 7)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.5), isLast ? Color.clear : tint.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 11)
        .accessibilityHidden(true)
    }

    private func rungHeader(_ section: ReviewSection, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ScanCopy.title(for: section.tier))
                        .font(.system(.headline, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("review.section.\(section.tier.rawValue)")

                    Eyebrow(DS.cost(section.tier), tint: tint)
                }

                Spacer(minLength: 8)

                // "None"/"All" read as labels for the current state rather than as the action
                // they perform, which is the wrong ambiguity on a screen that deletes things.
                Button {
                    model.setSelected(!model.selection.containsAll(section.candidateIDs), in: section)
                } label: {
                    Text(model.selection.containsAll(section.candidateIDs) ? "Deselect all" : "Select all")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.12))
                        )
                        // Measured at 34pt after the first pass. A control that selects a whole
                        // tier for deletion gets the full 44.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.selectall.\(section.tier.rawValue)")
            }

            HStack(spacing: 6) {
                Text(ByteFormatting.string(section.bytes))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text("across \(Counting.items(section.itemCount))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(ScanCopy.subtitle(for: section.tier))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A group row you can act on without opening it: the box ticks the whole group, the rest of
    /// the row goes in to look at the copies one by one.
    private func groupRow(_ group: ReviewGroup, tint: Color) -> some View {
        let selected = group.candidateIDs.filter { model.selection.isSelected($0) }.count
        let all = group.candidates.count

        return HStack(spacing: 0) {
            Button {
                withAnimation(Motion.control) {
                    model.setSelected(selected < all, in: group)
                }
            } label: {
                Image(systemName: boxSymbol(selected: selected, of: all))
                    .font(.title3)
                    .foregroundStyle(selected > 0 ? tint : Color.secondary)
                    .symbolEffect(.bounce, value: selected)
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected < all ? "Select every copy in this group" : "Deselect every copy in this group")
            .accessibilityValue("\(selected) of \(all) selected")
            .accessibilityIdentifier("review.group.\(group.id)")

            NavigationLink {
                GroupDetailView(group: group, model: model, loader: loader)
            } label: {
                GroupRowView(group: group, selectedCount: selected, tint: tint, loader: loader)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 12)
        .dsPanel(radius: 16)
    }

    private func boxSymbol(selected: Int, of total: Int) -> String {
        if selected == 0 { return "square" }
        return selected == total ? "checkmark.square.fill" : "minus.square.fill"
    }

    // MARK: - The bar

    /// What you are about to get back, not a red pill with an ellipsis on it.
    ///
    /// The reading leads; the meter under it says how much of everything on offer that is; and
    /// the key takes the colour of the dearest rung the selection reaches into, so a selection
    /// that costs nothing is not dressed up as a destructive act. Red is kept for the sheet that
    /// actually destroys something.
    private var reclaimBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.hairline)
                .frame(height: 1)

            MeterTrack(
                segments: [
                    MeterTrack.Segment(
                        id: "selected",
                        value: Double(model.savings.onDeviceBytes),
                        color: actionTint
                    )
                ],
                total: Double(max(model.maxReclaimableBytes, 1)),
                height: 4
            )
            .accessibilityHidden(true)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Eyebrow("You get back", tint: model.canDelete ? actionTint : Color.secondary)

                    Readout.bytes(
                        model.savings.onDeviceBytes,
                        scale: .title,
                        unitScale: .subheadline,
                        tint: model.canDelete ? actionTint : Color.secondary
                    )
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("review.total")

                    Text("\(model.selection.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("review.count")
                }

                Spacer(minLength: 8)

                Button {
                    showingConfirm = true
                } label: {
                    HStack(spacing: 7) {
                        Text(model.canDelete ? "Delete \(Counting.items(model.selection.count))" : "Delete")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.key(actionTint, enabled: model.canDelete, expands: false))
                .disabled(!model.canDelete)
                .accessibilityIdentifier("review.delete")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(.regularMaterial)
    }

    /// The dearest rung the selection reaches into. Nothing selected reads as the brand's teal —
    /// the colour of a deletion that costs nothing, which is where the app always starts.
    private var actionTint: Color {
        DS.tier(model.deepestSelectedTier ?? .identical)
    }

    // MARK: - Outcome

    private func outcomeSection(_ outcome: DeletionOutcome) -> some View {
        Card(rail: DS.tier(.inferiorCopy)) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("\(Counting.items(outcome.deletedCount)) removed")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.tier(.inferiorCopy))
                }
                .font(.system(.headline, design: .rounded))
                .accessibilityIdentifier("review.result")

                Text("The receipt is in History: what went, and what was kept in its place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("They are in Recently Deleted for 30 days. Empty that album in Photos to get the space back now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if outcome.skippedCount > 0 {
                    // Not a failure, a refusal — and the difference matters to someone deciding
                    // whether to trust this app with the rest of their library.
                    Text("\(Counting.items(outcome.skippedCount)) \(outcome.skippedCount == 1 ? "was" : "were") left alone: the file changed after the scan read it, so it is no longer the copy that was checked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("review.skipped")
                }

                if outcome.missingCount > 0 {
                    Text("\(Counting.items(outcome.missingCount)) \(outcome.missingCount == 1 ? "was" : "were") already gone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
