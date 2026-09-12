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
                    Card("Scan failed", symbolName: "exclamationmark.triangle", identifier: "scan.failure") {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
            .padding(.vertical, 12)
            .animation(Motion.content, value: model.isScanning)
            .animation(Motion.content, value: model.result?.candidates.count)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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

    private var introCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Scan \(Counting.items(items.count))")
                    .font(.title3.weight(.semibold))

                Text("Metadata is compared first, so only the handful of items that could possibly match ever get read. Nothing is downloaded from iCloud and nothing is deleted without you saying so.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                model.start(items: items)
            } label: {
                Text("Start scan")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("scan.start")
        }
    }

    private var progressCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(ScanCopy.title(for: model.progress?.stage ?? .bucketing))
                    .font(.headline)
                    .transition(.blurReplace)
                    .id(model.progress?.stage ?? .bucketing)
                    .accessibilityIdentifier("scan.stage")

                ProgressView(value: model.progress?.fraction ?? 0)

                Text(model.isPaused ? "Paused — nothing read so far is lost" : countsText)
                    .font(.footnote)
                    .foregroundStyle(model.isPaused ? Color.orange : Color.secondary)
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
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("scan.pause")

                Button {
                    model.cancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
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
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.title)
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: hasSettled)
                        .onAppear { hasSettled = true }
                    Text("No duplicates found")
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("scan.empty")
                    Text("Nothing in this library is a copy of anything else.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ByteFormatting.string(result.reclaimableBytes))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityIdentifier("scan.total")
                    Text("across \(Counting.items(result.candidates.count)) you could remove")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    ReviewView(result: result, history: history)
                } label: {
                    Text("Review and choose")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("scan.review")
            }

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
                }
            }
        }
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

    @ViewBuilder
    private func tierCard(_ summary: TierSummary) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: ScanCopy.symbolName(for: summary.tier))
                    .font(.title3)
                    .foregroundStyle(summary.tier.isLossless ? Color.green : Color.orange)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ScanCopy.title(for: summary.tier))
                        .font(.headline)
                        .lineLimit(2)
                        .accessibilityIdentifier("scan.tier.\(summary.tier.rawValue)")

                    Text(ScanCopy.subtitle(for: summary.tier))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormatting.string(summary.bytes))
                        .font(.subheadline.weight(.semibold))
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
