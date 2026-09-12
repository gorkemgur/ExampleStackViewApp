import SwiftUI
import UniformTypeIdentifiers
import DupeCore

struct RootView: View {

    /// Set by a link from the Live Activity or the widget. Consumed once, then cleared.
    @Binding var pendingLink: DeepLink?

    @EnvironmentObject private var history: HistoryViewModel
    @StateObject private var model = OverviewViewModel(
        library: AppEnvironment.makeLibrary(),
        folderRegistry: AppEnvironment.folderRegistry,
        changeObserver: AppEnvironment.makeChangeObserver()
    )
    @State private var pickingFolder = false
    @State private var showingLiveSurfaces = false
    @State private var path = NavigationPath()

    init(pendingLink: Binding<DeepLink?> = .constant(nil)) {
        _pendingLink = pendingLink
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    if let snapshot = model.storage {
                        StorageCardView(snapshot: snapshot, libraryBytes: model.onDeviceLibraryBytes)
                            .padding(.bottom, 2)
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
                        scanEntryPanel
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
                .padding(.top, 8)
                .padding(.bottom, 28)
                .animation(Motion.content, value: model.items.count)
                .animation(Motion.content, value: model.access)
                .animation(Motion.content, value: model.isLoading)
                .animation(Motion.content, value: model.folders)
            }
            .background(DS.ink, ignoresSafeAreaEdges: .all)
            .navigationTitle("DupeSpace")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await model.refresh()
            }
            .navigationDestination(for: DeepLink.self) { link in
                switch link {
                case .scan: ScanView(items: model.items, history: history)
                }
            }
            .toolbar {
                // The Lock Screen and the Dynamic Island cannot be walked to on a simulator, so
                // under test the app renders those same views itself and the walk photographs
                // them. Nothing here is reachable in a shipping build.
                if AppEnvironment.isUITesting {
                    ToolbarItem(placement: .topBarTrailing) {
                        // A glyph rather than the words: the bar also carries the title and the
                        // History reading, and "Live surfaces" spelled out crowds both off a
                        // phone. The label is unchanged, so the walk still finds it by name.
                        Button {
                            showingLiveSurfaces = true
                        } label: {
                            Image(systemName: "iphone.gen3")
                        }
                        .accessibilityLabel("Live surfaces")
                        .accessibilityIdentifier("root.livesurfaces")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    historyEntry
                }
            }
        }
        .sheet(isPresented: $showingLiveSurfaces) {
            LiveSurfacePreviewView { showingLiveSurfaces = false }
        }
        .task {
            await model.refresh()
            model.beginObservingLibrary()
        }
        .onChange(of: pendingLink) { _, link in
            guard let link else { return }
            // Replace rather than stack: two taps on the Live Activity must not leave two scan
            // screens on top of each other.
            path = NavigationPath()
            path.append(link)
            pendingLink = nil
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

    // MARK: - History

    /// The whole of the old History tab, in one control — and it carries a reading rather than
    /// just a word, so the chrome the tab bar used to cost is now telling you something.
    private var historyEntry: some View {
        NavigationLink {
            HistoryView()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption.weight(.bold))
                Text(historyChipTitle)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(DS.deep)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(DS.deep.opacity(0.13))
            )
        }
        .accessibilityLabel("History")
        .accessibilityHint("What this app has scanned and removed")
        .accessibilityIdentifier("history.open")
    }

    private var historyChipTitle: String {
        history.totalReclaimedBytes > 0 ? ByteFormatting.string(history.totalReclaimedBytes) : "History"
    }

    // MARK: - The invitation

    /// The one block on this screen that is not a card: a dark instrument panel carrying the
    /// ladder the whole product is built on, so the offer on the button is legible before it is
    /// tapped rather than after.
    private var scanEntryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow("The regret ladder", tint: DS.onSlabAccent)

                Text("Find what you can lose least")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Ranked by what deleting actually costs you — identical copies first, your judgement calls last.")
                    .font(.subheadline)
                    .foregroundStyle(DS.onSlab.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ladderPreview

            NavigationLink {
                ScanView(items: model.items, history: history)
            } label: {
                Text("Scan for duplicates")
            }
            .buttonStyle(.key)
            .accessibilityIdentifier("root.scan")
        }
        .dsSlab()
    }

    /// Four rungs, cheapest at the bottom of the cost scale and dearest at the top. The colours
    /// here are the same ones the review screen rails its groups with, so the ladder is learned
    /// once and read everywhere.
    private var ladderPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(RegretTier.allCases, id: \.self) { tier in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Capsule(style: .continuous)
                        .fill(DS.tierVivid(tier))
                        .frame(width: 3, height: 12)
                        .alignmentGuide(.firstTextBaseline) { $0.height - 1 }

                    Text(ScanCopy.title(for: tier))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.onSlab.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 8)

                    Eyebrow(DS.cost(tier), tint: DS.costTint(tier, onSlab: true))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The ladder: identical copies and lower-quality re-sends cost nothing, burst leftovers and similar shots are your call.")
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
        Card(
            "Could not read the library",
            symbolName: "exclamationmark.triangle",
            identifier: "library.failure",
            rail: DS.neutral
        ) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Authorised") {
    RootView()
        .environmentObject(HistoryViewModel(store: InMemoryHistoryStore()))
}
