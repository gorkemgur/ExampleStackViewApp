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

    // Main-actor because the thumbnail loader now takes the display scale, and `UIScreen.main`
    // is main-actor isolated. A SwiftUI view's `init` is not implicitly isolated — only `body`
    // is — so it has to be said.
    @MainActor
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
                    Card("Nothing was deleted", symbolName: "exclamationmark.triangle", identifier: "review.failure.title", rail: DS.neutral) {
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
            rail: DS.deep
        ) {
            Text("Everything this scan found has been dealt with. Scan again when the library has changed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The one control that makes this app what it is, so it gets the instrument panel: a dark
    /// slab, the target set as a gauge reading, and the ladder drawn into the fader's own
    /// track so the cost of a target is visible before the drag rather than after it.
    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("I need back", tint: DS.onSlabAccent)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Readout.bytes(Int64(model.budgetBytes), tint: DS.onSlabAccent)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("budget.target")

                    Spacer(minLength: 0)
                }
            }

            // A fader with the ladder drawn into its track, so the question "how far down does
            // this target make me go" is answered before the drag rather than after it.
            TargetSlider(
                value: $model.budgetBytes,
                range: 0...Double(max(model.maxReclaimableBytes, 1)),
                rungs: RegretTier.allCases.compactMap { tier in
                    let bytes = rungBytes(tier)
                    guard bytes > 0 else { return nil }
                    return TargetSlider.Rung(
                        id: "rung.\(tier.rawValue)",
                        bytes: bytes,
                        color: DS.tierVivid(tier)
                    )
                },
                reachLimit: reachableBytes,
                label: "Space to free",
                identifier: "budget.slider"
            )

            // One bar on this slab, and it is the fader. The depth is three chips.
            depthPicker

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

        }
        .dsSlab()
    }

    /// How far down the ladder the plan may reach.
    ///
    /// Equal steps, deliberately. These carried each rung's real byte weight, which put a
    /// rung-width ladder directly below the rung-width ladder in the fader's track — and in a
    /// library whose burst and similar rungs are empty, "No loss" took ninety-seven per cent
    /// of the bar, so the control read as one solid block and moving the selection changed
    /// nothing visible. One of the two says what each rung is worth, and that is the fader.
    /// This one says how far you are willing to go: three equal choices.
    private var depthPicker: some View {
        ReachPicker<RegretTier>(
            selection: $model.budgetDepth,
            options: [
                ReachPicker<RegretTier>.Option(value: .inferiorCopy, title: "No loss", color: DS.tierVivid(.inferiorCopy)),
                ReachPicker<RegretTier>.Option(value: .burstLeftover, title: "+ bursts", color: DS.tierVivid(.burstLeftover)),
                ReachPicker<RegretTier>.Option(value: .similar, title: "+ similar", color: DS.tierVivid(.similar))
            ],
            identifier: "budget.depth",
            onSlab: true
        )
    }

    /// What the current depth setting can actually reach, which is where the fader stops
    /// offering. Everything past this is real space the plan will not take.
    private var reachableBytes: Double {
        RegretTier.allCases
            .filter { $0 <= model.budgetDepth }
            .reduce(0) { $0 + rungBytes($1) }
    }

    private func rungBytes(_ tier: RegretTier) -> Double {
        Double(model.sections.first { $0.tier == tier }?.bytes ?? 0)
    }

    private var planSummary: String {
        let plan = model.budgetPlan
        guard !plan.selected.isEmpty else {
            return "Drag to set a target. Nothing is selected by a plan of zero."
        }
        let reached = ByteFormatting.string(plan.reclaimedBytes)
        let deepest = plan.deepestTier.map { ScanCopy.title(for: $0).lowercased() } ?? "nothing"
        if plan.meetsTarget {
            // Not the count and not the bytes: the dock says both, verbatim, and the readout
            // sixty points above says the bytes again. What nothing else on the screen says is
            // how deep this plan actually had to go.
            return "Reaches as far as \(deepest)."
        }
        return "Only \(reached) is available at this setting (\(Counting.items(plan.selected.count))). Allow more, or accept less."
    }

    // MARK: - The ladder

    /// Lazy, and it has to be said out loud because the outer `LazyVStack` was doing nothing
    /// for it.
    ///
    /// A lazy stack only defers the children it owns directly. `ladder` is a single child of
    /// the one at the top of this file, so the moment it came into view every section and
    /// every group inside it was built at once — and each group row holds a `ThumbnailView`
    /// whose `.task` fires on appear. A hundred and seventy items form about eighty-five
    /// groups: eighty-five rows and eighty-five PhotoKit requests, all on the first frame, for
    /// a screen showing six of them.
    private var ladder: some View {
        let sections = model.visibleSections
        return LazyVStack(alignment: .leading, spacing: 0) {
            if model.availableKinds.count > 1 {
                kindFilter
                    .padding(.bottom, DS.Space.l)
            }

            if sections.isEmpty {
                Text("Nothing of that kind in this scan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Space.l)
            } else {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    rung(section, isLast: index == sections.count - 1)
                }
            }
        }
        .animation(Motion.content, value: model.kindFilter)
    }

    /// Photos, videos and files share every tier, because what deleting something costs you has
    /// nothing to do with what kind of thing it is. But videos are where the bytes are, and
    /// "just show me those" was not askable. A filter rather than a second level of section:
    /// splitting each tier by kind would double the headings and bury the decision.
    private var kindFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s) {
                filterChip(nil)
                ForEach(model.availableKinds, id: \.self) { kind in
                    filterChip(kind)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("review.kinds")
    }

    private func filterChip(_ kind: MediaKind?) -> some View {
        let selected = model.kindFilter == kind
        let tally = model.tally(for: kind)

        return Button {
            model.kindFilter = kind
        } label: {
            HStack(spacing: 6) {
                Image(systemName: KindCopy.symbolName(for: kind))
                    .font(.caption2.weight(.bold))
                Text(KindCopy.title(for: kind))
                    .font(.footnote.weight(selected ? .bold : .medium))
                Text(ByteFormatting.string(tally.bytes))
                    .font(.caption2)
                    .monospacedDigit()
                    .opacity(0.75)
            }
            .foregroundStyle(selected ? DS.deep : Color.secondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? DS.deep.opacity(0.13) : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(selected ? DS.deep.opacity(0.45) : DS.hairline, lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(KindCopy.title(for: kind)), \(Counting.items(tally.items))")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("review.kind.\(kind.map(String.init(describing:)) ?? "all")")
    }

    private func rung(_ section: ReviewSection, isLast: Bool) -> some View {
        let tint = DS.tier(section.tier)

        return HStack(alignment: .top, spacing: 14) {
            rail(tint: tint, isLast: isLast)

            VStack(alignment: .leading, spacing: 12) {
                rungHeader(section, tint: tint)

                LazyVStack(spacing: 8) {
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

                    Eyebrow(DS.cost(section.tier), tint: DS.costTint(section.tier))
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
                // No bounce. It fired on every checkbox, so ticking thirty groups was thirty
                // pieces of decoration on a screen about choices that cannot be taken back.
                // The mark changing is the feedback.
                TickBox(state: boxMark(selected: selected, of: all), tint: tint)
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

    private func boxMark(selected: Int, of total: Int) -> TickBox.Mark {
        if selected == 0 { return .empty }
        return selected == total ? .full : .partial
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
            .padding(.horizontal, 18)
            .padding(.top, 16)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Eyebrow("You get back", tint: model.canDelete ? DS.deep : Color.secondary)

                    Readout.bytes(
                        model.savings.onDeviceBytes,
                        scale: .title,
                        unitScale: .subheadline,
                        tint: model.canDelete ? DS.deep : Color.secondary
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
                // The app's own action, in the app's own colour.
                //
                // This used to be `actionTint` — the deepest selected tier — so the most
                // consequential button in the product was green on the review screen and red
                // one tap later on the confirmation, and neither hue was the colour of
                // anything else this app does. What the selection costs is already said three
                // times in this dock; it is said once now, on the meter above, where a
                // proportion belongs.
                .buttonStyle(.key(enabled: model.canDelete, expands: false))
                .disabled(!model.canDelete)
                .accessibilityIdentifier("review.delete")
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        // A dock that floats, not a strip welded to the bottom edge.
        //
        // It was an edge-to-edge `.regularMaterial` band with a hairline across the top — the
        // shape every iOS app has had at the bottom of a screen since 2013, and the thing this
        // one is most often mistaken for. Inset and rounded, it reads as a control panel
        // resting on the list rather than as chrome the list ends at, and the content scrolls
        // visibly underneath it.
        .dsDock()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// The dearest rung the selection reaches into. Drawn on the meter and nowhere else: it is
    /// a reading about the selection, not the identity of the button beside it.
    private var actionTint: Color {
        DS.tier(model.deepestSelectedTier ?? .identical)
    }

    // MARK: - Outcome

    private func outcomeSection(_ outcome: DeletionOutcome) -> some View {
        // Not `tier(.inferiorCopy)`. Green was doing three jobs in this app — a rung of the
        // ladder, "it worked", and "this is the copy that stays" — and a hue that means three
        // things means none of them.
        Card(rail: DS.deep) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("\(Counting.items(outcome.deletedCount)) removed")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.deep)
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
