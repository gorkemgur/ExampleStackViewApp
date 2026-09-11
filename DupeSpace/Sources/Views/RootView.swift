import SwiftUI
import DupeCore

struct RootView: View {

    @StateObject private var model = OverviewViewModel(library: AppEnvironment.makeLibrary())

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let snapshot = model.storage {
                        StorageCardView(snapshot: snapshot, libraryBytes: model.onDeviceLibraryBytes)
                    }

                    if model.access != .authorized {
                        AccessCardView(access: model.access) {
                            Task { await model.requestAccess() }
                        }
                    }

                    if model.isLoading {
                        loadingCard
                    }

                    if let message = model.failureMessage {
                        failureCard(message)
                    }

                    if !model.breakdown.isEmpty {
                        BreakdownCardView(breakdown: model.breakdown, totalBytes: model.libraryBytes)
                    }

                    if !model.largestItems.isEmpty {
                        LargestItemsCardView(items: model.largestItems)
                    }

                    LimitsCardView(cloudOnlyBytes: model.cloudOnlyBytes)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("DupeSpace")
            .refreshable {
                await model.refresh()
            }
        }
        .task {
            await model.refresh()
        }
    }

    private var loadingCard: some View {
        Card {
            HStack(spacing: 12) {
                ProgressView()
                Text("Reading library metadata…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("library.loading")
            }
        }
    }

    private func failureCard(_ message: String) -> some View {
        Card("Could not read the library", symbolName: "exclamationmark.triangle", identifier: "library.failure") {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Authorised") {
    RootView()
}
