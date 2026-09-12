import SwiftUI
import DupeCore

struct ScanView: View {

    let items: [MediaItem]

    private let history: HistoryViewModel
    @StateObject private var model: ScanViewModel
    /// Set once the results have appeared, so the seal bounces on arrival rather than never.
    @State private var hasSettled = false

    init(items: [MediaItem], history: HistoryViewModel) {
        self.items = items
        self.history = history
        _model = StateObject(
            wrappedValue: ScanViewModel(
                analyzer: AppEnvironment.makeAnalyzer(),
                history: history,
                cache: AppEnvironment.fingerprintCache,
                activity: AppEnvironment.makeScanActivity()
            )
        )
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
        }
        .background(DS.ink, ignoresSafeAreaEdges: .all)
        .sensoryFeedback(.success, trigger: model.result != nil) { _, hasResult in hasResult }
        .navigationTitle("Find duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Leaving the screen must stop the work, not leave it reading the library in the
            // background with nowhere to report to.
            model.cancel()
        }
    }

    // MARK: - States

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

                Text("Metadata is compared first, so only the handful of items that could possibly match ever get read. Nothing is downloaded from iCloud and nothing is deleted without you saying so.")
                    .font(.subheadline)
                    .foregroundStyle(DS.onSlab.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
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
                    Text("Nothing in this library is a copy of anything else.")
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
                ReviewView(result: result, history: history)
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

    /// One rung of the ladder, carrying its own colour — the same colour the review screen
    /// rails that tier with, so the two screens are plainly describing the same thing.
    @ViewBuilder
    private func tierCard(_ summary: TierSummary) -> some View {
        Card(rail: DS.tier(summary.tier)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: ScanCopy.symbolName(for: summary.tier))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(DS.tier(summary.tier))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DS.tier(summary.tier).opacity(0.13))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(ScanCopy.title(for: summary.tier))
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(2)
                        .accessibilityIdentifier("scan.tier.\(summary.tier.rawValue)")

                    Eyebrow(DS.cost(summary.tier), tint: DS.costTint(summary.tier))

                    Text(ScanCopy.subtitle(for: summary.tier))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormatting.string(summary.bytes))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text(Counting.items(summary.itemCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            }
        }
    }
}
