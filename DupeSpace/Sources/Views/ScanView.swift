import SwiftUI
import DupeCore

struct ScanView: View {

    let items: [MediaItem]

    @StateObject private var model = ScanViewModel(analyzer: AppEnvironment.makeAnalyzer())

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let result = model.result {
                    resultsSection(result)
                } else if model.isScanning {
                    progressCard
                } else {
                    introCard
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
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
                Text("Scan \(items.count) items")
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
                    .accessibilityIdentifier("scan.stage")

                ProgressView(value: model.progress?.fraction ?? 0)

                Text(countsText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("scan.counts")
            }

            Button(role: .destructive) {
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
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .accessibilityIdentifier("scan.total")
                    Text("across \(result.candidates.count) items you could remove")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(summaries) { summary in
                tierCard(summary)
            }

            if !result.cloudOnlyIDs.isEmpty {
                Card("Not checked", symbolName: "icloud", identifier: "scan.cloud") {
                    Text("\(result.cloudOnlyIDs.count) items have their original in iCloud. They were left alone rather than downloaded over your connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                        .accessibilityIdentifier("scan.tier.\(summary.tier.rawValue)")

                    Text(ScanCopy.subtitle(for: summary.tier))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormatting.string(summary.bytes))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("\(summary.itemCount) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
