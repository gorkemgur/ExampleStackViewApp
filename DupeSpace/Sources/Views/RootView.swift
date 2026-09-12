import SwiftUI
import UniformTypeIdentifiers
import DupeCore

struct RootView: View {

    @EnvironmentObject private var history: HistoryViewModel
    @StateObject private var model = OverviewViewModel(
        library: AppEnvironment.makeLibrary(),
        folderRegistry: AppEnvironment.folderRegistry,
        changeObserver: AppEnvironment.makeChangeObserver()
    )
    @State private var pickingFolder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let snapshot = model.storage {
                        StorageCardView(snapshot: snapshot, libraryBytes: model.onDeviceLibraryBytes)
                            .cardEntrance()
                    }

                    if model.access != .authorized {
                        AccessCardView(access: model.access) {
                            Task { await model.requestAccess() }
                        }
                        .cardEntrance()
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }

                    if model.isLoading {
                        loadingCard
                    }

                    if let message = model.failureMessage {
                        failureCard(message)
                    }

                    if !model.items.isEmpty {
                        scanEntryCard
                            .cardEntrance()
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }

                    FoldersCardView(
                        folders: model.folders,
                        message: model.folderMessage,
                        onAdd: { pickingFolder = true },
                        onRemove: { id in Task { await model.removeFolder(id: id) } }
                    )
                    .cardEntrance()

                    if !model.breakdown.isEmpty {
                        BreakdownCardView(breakdown: model.breakdown, totalBytes: model.libraryBytes)
                            .cardEntrance()
                    }

                    if !model.largestItems.isEmpty {
                        LargestItemsCardView(items: model.largestItems)
                            .cardEntrance()
                    }

                    LimitsCardView(cloudOnlyBytes: model.cloudOnlyBytes)
                        .cardEntrance()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.snappy(duration: 0.35), value: model.items.count)
                .animation(.snappy(duration: 0.3), value: model.access)
                .animation(.snappy(duration: 0.3), value: model.isLoading)
                .animation(.snappy(duration: 0.3), value: model.folders)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("DupeSpace")
            .refreshable {
                await model.refresh()
            }
        }
        .task {
            await model.refresh()
            model.beginObservingLibrary()
        }
        .fileImporter(
            isPresented: $pickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { await model.addFolder(at: url) }
        }
    }

    private var scanEntryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Find what you can lose least")
                    .font(.title3.weight(.semibold))
                Text("Ranked by what deleting actually costs you — identical copies first, your judgement calls last.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NavigationLink {
                ScanView(items: model.items, history: history)
            } label: {
                Text("Scan for duplicates")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("root.scan")
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
        .environmentObject(HistoryViewModel(store: InMemoryHistoryStore()))
}
