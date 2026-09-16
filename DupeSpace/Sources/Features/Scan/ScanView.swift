import SwiftUI
import DupeCore

struct ScanView: View {

    let items: [MediaItem]

    private let container: AppContainer
    private let history: HistoryViewModel
    @ObservedObject private var model: ScanStore
    /// Set once the results have appeared, so the seal bounces on arrival rather than never.
    @State private var hasSettled = false
    /// Drives the marker beside the running stage. Started when the scan starts, and never
    /// started at all under Reduce Motion.
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// What the scan is about to do, worked out from metadata alone. Off the main actor and
    /// once per appearance: it sorts and windows the whole library, which is nothing at
    /// twenty-eight items and is not nothing at fifty thousand.
    @State private var plan: ScanPlan?

    /// Main-actor for the same reason `ReviewView.init` is: `AppContainer` is isolated to it,
    /// and a view's `init` is not implicitly isolated the way `body` is.
    @MainActor
    init(container: AppContainer, items: [MediaItem], history: HistoryViewModel) {
        self.container = container
        self.items = items
        self.history = history
        // Observed, not owned. The scan belongs to `AppContainer` and outlives this screen —
        // which is the whole of Faz 5, and the reason the `onDisappear` that used to cancel it
        // is gone.
        _model = ObservedObject(wrappedValue: container.scan)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let result = model.result {
                    resultsSection(result)
                        .transition(.opacity.combined(with: .offset(y: 16)))
                } else if model.isScanning {
                    progressCard
                        .transition(.opacity)
                    scanningDetail
                        .transition(.opacity)
                } else {
                    introCard
                        .transition(.opacity)
                }

                if let failure = model.failure {
                    Card("Scan failed", symbolName: "exclamationmark.triangle", identifier: "scan.failure", rail: DS.neutral) {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if model.wasCancelled {
                    Card {
                        Text("Scan cancelled. Nothing was changed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("scan.cancelled")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
            .animation(Motion.content, value: model.isScanning)
            .animation(Motion.content, value: model.result?.candidates.count)
            .animation(Motion.content, value: plan)
        }
        .background(DS.ink, ignoresSafeAreaEdges: .all)
        .sensoryFeedback(.success, trigger: model.result != nil) { _, hasResult in hasResult }
        .navigationTitle("Find duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: items.count) {
            let snapshot = items
            plan = await Task.detached(priority: .userInitiated) {
                ScanPlan.of(snapshot)
            }.value
        }
        .onChange(of: model.isScanning) { _, scanning in
            guard !reduceMotion else { return }
            if scanning {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
    }

    // MARK: - States

    /// What there is to look at while the scan runs.
    ///
    /// Pressing Start used to empty the screen. The intro card — which carries the ledger, the
    /// one thing on here worth reading — was replaced by a single progress card, and `DS.ink`
    /// is `0x080C11` in dark mode, so what a person on a real phone actually got was one small
    /// card floating on a field of near-black for as long as the scan took. On a twenty-eight
    /// item fixture that is a moment. On somebody's real library it is minutes.
    ///
    /// Nothing here is invented to fill space. The ledger is the same ledger, still true, and
    /// now checkable against the counts moving above it. The ladder is the pipeline's own
    /// stages, which the app already knew and never showed: six of them, in order, with the
    /// finished ones struck through. That is a shape you can watch without it claiming a
    /// percentage the meter has not earned.
    ///
    /// Deliberately not `SweeperRingView`, which exists and would have been the quick answer:
    /// it is a figure sweeping a floor, the app's picture of *deleting*. Putting it here would
    /// tell somebody their photographs were being swept up while they were being read.
    private var scanningDetail: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Eyebrow("Reading now", tint: DS.onSlabAccent)
                stageLadder
            }

            if let plan, !plan.isEmpty {
                ledger(plan)
            }
        }
        .dsSlab()
    }

    /// The pipeline's stages, in the order it runs them.
    private var stageLadder: some View {
        let current = model.progress?.stage ?? .bucketing
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(ScanProgress.Stage.allCases, id: \.self) { stage in
                stageRow(stage, current: current)
            }
        }
        .animation(Motion.content, value: current)
        // The same trap as `scan.plan` and `review.order`: without `.contain` this identifier
        // is worn by all six rows and overrides theirs.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.stages")
    }

    private func stageRow(_ stage: ScanProgress.Stage, current: ScanProgress.Stage) -> some View {
        let isDone = stage.rawValue < current.rawValue
        let isCurrent = stage == current

        return HStack(spacing: DS.Space.s) {
            ZStack {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(DS.onSlabAccent)
                } else if isCurrent {
                    Circle()
                        .fill(DS.onSlabAccent)
                        .frame(width: 8, height: 8)
                        // The only moving thing on the screen that is not a measurement, and it
                        // is deliberately not one: it marks where you are, it does not claim
                        // progress. Off entirely under Reduce Motion — a pulse that cannot be
                        // switched off is the sort of thing this app's audit exists to catch.
                        .scaleEffect(reduceMotion ? 1 : (pulse ? 1.5 : 1))
                        .opacity(reduceMotion ? 1 : (pulse ? 0.5 : 1))
                } else {
                    Circle()
                        .fill(DS.onSlabWaitingMark)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 20, height: 20)

            Text(ScanCopy.title(for: stage))
                .font(.footnote.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(
                    isCurrent ? DS.onSlab : (isDone ? DS.onSlabDone : DS.onSlabWaiting)
                )
                .strikethrough(isDone, color: DS.onSlab.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ScanCopy.title(for: stage))
        .accessibilityValue(isDone ? "done" : (isCurrent ? "running" : "waiting"))
    }

    /// The invitation to scan, on the slab.
    ///
    /// It was a white card on the pale page, alone above six hundred points of nothing — and it
    /// offers the same action, with the same two controls, as the panel on the overview, which
    /// is drawn on the slab. The same act on two adjacent screens was made of two different
    /// materials.
    private var introCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Eyebrow("About to read", tint: DS.onSlabAccent)

                Text("Scan \(Counting.items(items.count))")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(DS.onSlab)

                // This said "only the handful of items that could possibly match ever get
                // read", which was a comforting sentence the pipeline contradicts eighty lines
                // later: every photograph on the device is opened and fingerprinted, because
                // two shots of the same moment share no byte and no file size. An app that
                // asks to be trusted with someone's photographs does not get to round that
                // off, so it now says what happens and then shows the count.
                Text("Every photo is opened once and fingerprinted — two pictures of the same moment share no byte and no file size, so there is no cheaper way to find them. A video is only opened when another is nearly the same length. Nothing is downloaded from iCloud, and nothing is deleted without you saying so.")
                    .font(.subheadline)
                    .foregroundStyle(DS.onSlab.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let plan, !plan.isEmpty {
                ledger(plan)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Strict → Balanced → Loose is a scale too, and the direction matters: each
                // step further along accepts more as a copy. The track says how far.
                ReachPicker<ScanStrictness>(
                    selection: $model.strictness,
                    options: ScanStrictness.allCases.map { level in
                        ReachPicker<ScanStrictness>.Option(
                            value: level,
                            title: level.title,
                            color: DS.tierVivid(level.reach)
                        )
                    },
                    identifier: "scan.strictness",
                    onSlab: true
                )

                Text(model.strictness.explanation)
                    .font(.caption)
                    .foregroundStyle(DS.onSlab.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .id(model.strictness)
                    .transition(.opacity)
                    .accessibilityIdentifier("scan.strictness.explanation")
            }
            .animation(Motion.control, value: model.strictness)

            Button {
                model.start(items: items)
            } label: {
                Text("Start scan")
            }
            .buttonStyle(.key)
            .accessibilityIdentifier("scan.start")
        }
        .dsSlab()
    }

    /// What is about to be opened, kind by kind.
    ///
    /// The screen used to be one card of prose above six hundred points of nothing, on top of
    /// a screen whose only other content was a button the previous screen already had. This is
    /// what it was missing: the reading itself, stated before it happens, in numbers the
    /// person can check afterwards against the result.
    private func ledger(_ plan: ScanPlan) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("\(plan.read) of \(plan.indexed) will be opened")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.onSlabAccent)
                .accessibilityIdentifier("scan.plan.summary")

            VStack(spacing: 0) {
                ForEach(Array(plan.lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 {
                        Divider().overlay(DS.onSlab.opacity(0.12))
                    }
                    ledgerRow(line)
                }
            }
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.onSlab.opacity(0.06))
            )

            ForEach(caveats(plan), id: \.self) { caveat in
                Text(caveat)
                    .font(.caption)
                    .foregroundStyle(DS.onSlab.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // See the note beside `review.order`: without `.contain`, this identifier is inherited
        // by every row, figure and caveat inside the ledger and overrides theirs. Ten separate
        // elements were wearing the name `scan.plan`, including the one the scan screen's own
        // test waits for.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.plan")
    }

    private func ledgerRow(_ line: ScanPlan.Line) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: KindCopy.symbolName(for: line.kind))
                .font(.footnote.weight(.bold))
                .foregroundStyle(DS.onSlabAccent)
                .frame(width: 20)

            Text(KindCopy.title(for: line.kind))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.onSlab)

            Spacer(minLength: DS.Space.s)

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(line.indexed) · \(ByteFormatting.string(line.bytes))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(DS.onSlab.opacity(0.85))

                Text(Self.readPhrase(line))
                    .font(.caption2)
                    .foregroundStyle(DS.onSlab.opacity(0.55))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// Said in words rather than as a second pair of numbers, because "12 · 12" reads as a
    /// typo and "all of them opened" reads as a fact.
    private static func readPhrase(_ line: ScanPlan.Line) -> String {
        if line.read == 0 { return "none opened" }
        if line.read == line.indexed { return "all opened" }
        return "\(line.read) opened"
    }

    private func caveats(_ plan: ScanPlan) -> [String] {
        var lines: [String] = []
        if plan.cloudOnly > 0 {
            lines.append(
                "\(Counting.items(plan.cloudOnly)) only exist in iCloud. They are set aside before "
                + "anything is read — opening one would mean downloading it."
            )
        }
        if plan.fromFolders > 0 {
            lines.append(
                "\(Counting.items(plan.fromFolders)) come from folders you handed over. Deleting "
                + "one of those is immediate; there is no Recently Deleted for them."
            )
        }
        return lines
    }

    private var progressCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(ScanCopy.title(for: model.progress?.stage ?? .bucketing))
                    .font(.system(.headline, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    // Not `.blurReplace`. `Card` argues two files away that a blurred card
                    // reads as a rendering fault rather than as a transition, and that applies
                    // just as well to the line telling you what the scan is doing.
                    .transition(.opacity)
                    .id(model.progress?.stage ?? .bucketing)
                    .accessibilityIdentifier("scan.stage")

                // The same track shape the disk gauge and the ladder use, rather than a stock
                // ProgressView, so a measurement always looks like a measurement in this app.
                MeterTrack(
                    segments: [
                        MeterTrack.Segment(
                            id: "progress",
                            value: model.progress?.fraction ?? 0,
                            color: model.isPaused ? DS.tier(.burstLeftover) : DS.brandBottom
                        )
                    ],
                    total: 1,
                    height: 8,
                    motion: Motion.readout
                )
                .accessibilityElement()
                .accessibilityLabel("Scan progress")
                .accessibilityValue("\(Int(((model.progress?.fraction ?? 0) * 100).rounded())) percent")

                Text(model.isPaused ? "Paused — nothing read so far is lost" : countsText)
                    .font(.footnote)
                    .foregroundStyle(model.isPaused ? DS.tier(.burstLeftover) : Color.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("scan.counts")
            }
            .animation(Motion.content, value: model.progress?.stage)
            .animation(Motion.control, value: model.isPaused)

            HStack(spacing: 10) {
                // Pausing keeps everything read so far. Cancelling throws it away, which is
                // rarely what someone wants when the phone just got warm.
                Button {
                    if model.isPaused {
                        model.resume()
                    } else {
                        model.pause()
                    }
                } label: {
                    Label(
                        model.isPaused ? "Resume" : "Pause",
                        systemImage: model.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(.keyQuiet)
                .accessibilityIdentifier("scan.pause")

                Button {
                    model.cancel()
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(.keyQuiet)
                .accessibilityIdentifier("scan.cancel")
            }
        }
    }

    private var countsText: String {
        guard let progress = model.progress, progress.total > 0 else { return "Preparing…" }
        return "\(progress.completed) of \(progress.total)"
    }

    @ViewBuilder
    private func resultsSection(_ result: ScanResult) -> some View {
        let summaries = result.tierSummaries

        if summaries.isEmpty {
            Card(rail: DS.deep) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.title)
                        .foregroundStyle(DS.deep)
                        .symbolEffect(.bounce, value: hasSettled)
                        .onAppear { hasSettled = true }
                    Text("No duplicates found")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .accessibilityIdentifier("scan.empty")
                    Text("Nothing in this library is a copy of anything else at this setting.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            resultsHeadline(result)

            ForEach(summaries) { summary in
                tierCard(summary)
                    .cardEntrance()
            }

            let lookalikes = NameHeuristic.clusters(
                for: result.items.values.filter { $0.source == .fileFolder },
                excluding: Set(result.groups.flatMap(\.itemIDs))
            )
            if !lookalikes.isEmpty {
                nameLookalikeCard(lookalikes, items: result.items)
            }

            if !result.cloudOnlyIDs.isEmpty {
                Card("Not checked", symbolName: "icloud", identifier: "scan.cloud") {
                    Text("\(Counting.items(result.cloudOnlyIDs.count)) \(result.cloudOnlyIDs.count == 1 ? "has" : "have") the original in iCloud. They were left alone rather than downloaded over your connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        rescanPanel
    }

    /// The way back to a second scan.
    ///
    /// This screen had exactly one state after a scan finished, and it was terminal. The intro
    /// card — which carries the strictness control and the only "Start scan" in the app — is
    /// drawn when `result` is nil, and `result` stops being nil the moment the first scan ends.
    /// So "No duplicates found" on Strict was the end of the road: the one thing a person
    /// obviously wants next, try it looser, could not be reached without leaving the screen and
    /// coming back. Worse for an empty result, where there is nothing else on the screen at all.
    private var rescanPanel: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Eyebrow("Try again", tint: DS.onSlabAccent)

            ReachPicker<ScanStrictness>(
                selection: $model.strictness,
                options: ScanStrictness.allCases.map { level in
                    ReachPicker<ScanStrictness>.Option(
                        value: level,
                        title: level.title,
                        color: DS.tierVivid(level.reach)
                    )
                },
                identifier: "scan.rescan.strictness",
                onSlab: true
            )

            Text(model.strictness.explanation)
                .font(.caption)
                .foregroundStyle(DS.onSlab.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .id(model.strictness)
                .transition(.opacity)

            Button {
                model.start(items: items)
            } label: {
                Text("Scan again")
            }
            .buttonStyle(.keyOnSlab)
            .accessibilityIdentifier("scan.rescan")

            Text("Nothing you have already deleted comes back, and nothing is deleted by scanning.")
                .font(.caption)
                .foregroundStyle(DS.onSlab.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(Motion.control, value: model.strictness)
        .dsSlab()
    }

    /// What the scan found, on the instrument panel — the same slab the space budget uses,
    /// because this figure is the one the budget is about to be spent against.
    private func resultsHeadline(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("What the scan found", tint: DS.onSlabAccent)

                Readout.bytes(result.reclaimableBytes, tint: DS.onSlabAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("scan.total")

                Text("across \(Counting.items(result.candidates.count)) you could remove")
                    .font(.subheadline)
                    .foregroundStyle(DS.onSlab.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            MeterTrack(
                segments: result.tierSummaries.map {
                    MeterTrack.Segment(
                        id: "found.\($0.tier.rawValue)",
                        value: Double($0.bytes),
                        color: DS.tierVivid($0.tier)
                    )
                },
                total: Double(max(result.reclaimableBytes, 1)),
                height: 8
            )
            .accessibilityHidden(true)

            NavigationLink {
                ReviewView(container: container, result: result, history: history)
            } label: {
                Text("Review and choose")
            }
            .buttonStyle(.key)
            .accessibilityIdentifier("scan.review")
        }
        .dsSlab()
    }

    /// Files whose names say "copy" but whose contents do not match.
    ///
    /// Shown, never offered for deletion. A name is a hint about a file, not evidence about
    /// its contents, and the difference is the whole reason this app can be trusted.
    @ViewBuilder
    private func nameLookalikeCard(_ clusters: [NameCluster], items: [String: MediaItem]) -> some View {
        Card("Named like copies, but not copies", symbolName: "text.magnifyingglass", identifier: "scan.lookalikes") {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(Counting.items(clusters.count)) share a name with something else but hold different content. Nothing here is selected or counted — it is only worth your eyes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(clusters.prefix(5)) { cluster in
                    let names = cluster.itemIDs.compactMap { items[$0]?.displayName }
                    Text(names.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }
        }
    }

    /// Past `.accessibility1` the rung's two columns become two rows.
    ///
    /// Two things in the row refuse to shrink, each for a good reason: the badge asks for its
    /// own width so two words never wrap inside a capsule, and the bytes column is `fixedSize`
    /// so a figure never ellipsises to "180,4…". Side by side at AX5 that is 244 + 12 + 8 + 220
    /// = 484pt of demands against the 300pt a card has inside its padding on a 390pt phone —
    /// and a card that cannot be drawn is not scrolled to, it is clipped at both edges. Worse,
    /// a `VStack` proposes its final width to every child at placement, so one 548pt card
    /// widened the headline slab and the caveats with it: the whole screen sat 79pt off the
    /// left. Under each other, 244 and 220 fit in 300 with room to spare, so nothing has to
    /// give up the width it was told to keep. Same threshold as `ReachPicker`.
    private var tierCardStacked: Bool { typeSize >= .accessibility1 }

    /// One rung of the ladder, carrying its own colour — the same colour the review screen
    /// rails that tier with, so the two screens are plainly describing the same thing.
    @ViewBuilder
    private func tierCard(_ summary: TierSummary) -> some View {
        let stacked = tierCardStacked
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        Card(rail: DS.tier(summary.tier)) {
            layout {
                VStack(alignment: .leading, spacing: 6) {
                    // The glyph inline, unboxed, the way `Card` has drawn its own since the
                    // tinted icon slot was taken out of it — "every settings row in every app",
                    // and saying nothing the rail beside it does not already say in the same
                    // colour. Here it was worse than generic: a pale tinted square sat directly
                    // above a badge of the same hue at full strength, so the card carried one
                    // colour twice in the same column, once washed out and once solid.
                    HStack(spacing: 7) {
                        Image(systemName: ScanCopy.symbolName(for: summary.tier))
                            .font(.subheadline.weight(.semibold))
                            .imageScale(.small)
                            .foregroundStyle(DS.tier(summary.tier))

                        Text(ScanCopy.title(for: summary.tier))
                            .font(.system(.headline, design: .rounded))
                            // Stacked, the width is no longer the scarce thing.
                            .lineLimit(stacked ? nil : 2)
                            .accessibilityIdentifier("scan.tier.\(summary.tier.rawValue)")
                    }

                    Badge(DS.cost(summary.tier), tint: DS.costTint(summary.tier))

                    Text(ScanCopy.subtitle(for: summary.tier))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !stacked {
                    Spacer(minLength: 8)
                }

                VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
                    Text(ByteFormatting.string(summary.bytes))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .accessibilityIdentifier("scan.tier.\(summary.tier.rawValue).bytes")
                    Text(Counting.items(summary.itemCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(stacked ? nil : 1)
                // Beside the text column the figure keeps its width and wins the contest for
                // it. Under the text column there is no contest, and a column that will not
                // shrink is exactly what put the card off the phone.
                .fixedSize(horizontal: !stacked, vertical: true)
                .layoutPriority(stacked ? 0 : 1)
            }
        }
    }
}
