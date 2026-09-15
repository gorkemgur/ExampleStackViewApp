import SwiftUI
import UniformTypeIdentifiers
import DupeCore

struct RootView: View {

    /// Set by a link from the Live Activity or the widget. Consumed once, then cleared.
    @Binding var pendingLink: DeepLink?

    @EnvironmentObject private var history: HistoryViewModel
    /// The app's services. Read in `init` rather than through the environment, which a view's
    /// `init` cannot reach — and this screen's model has to be built there to stay a single
    /// `@StateObject`.
    private let container: AppContainer
    @StateObject private var model: OverviewViewModel
    /// Observed, not owned — the scan belongs to `AppContainer`. This screen watches it only so
    /// the strip above the stack has something to redraw against; nothing here starts, stops or
    /// holds a scan.
    @ObservedObject private var scan: ScanStore
    /// Re-reading the permission needs to know when the app comes back to the front. The
    /// permission alert itself, the Settings round trip the access card offers, and a
    /// revocation while backgrounded all land here and nowhere else.
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickingFolder = false
    @State private var showingLiveSurfaces = false
    @State private var path = NavigationPath()
    /// Decided once, at the first construction of this view, and not re-asked afterwards: a
    /// value that re-evaluated on every redraw would put the screen back up the moment
    /// `markSeen()` had not yet been written.
    @State private var showingOnboarding: Bool

    /// Main-actor because `AppContainer` is, and a SwiftUI view's `init` is not implicitly
    /// isolated — only `body` is. The same reason `ReviewView.init` says so.
    @MainActor
    init(container: AppContainer, pendingLink: Binding<DeepLink?> = .constant(nil)) {
        _pendingLink = pendingLink
        self.container = container
        _scan = ObservedObject(wrappedValue: container.scan)
        _model = StateObject(
            wrappedValue: OverviewViewModel(
                library: container.library,
                folderRegistry: container.folderRegistry,
                changeObserver: container.changeObserver
            )
        )
        _showingOnboarding = State(
            initialValue: OnboardingGate.shouldPresent(
                hasSeen: container.onboardingStore.hasSeenOnboarding,
                isUITesting: AppEnvironment.isUITesting,
                isForced: AppEnvironment.isForcingOnboarding
            )
        )
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

                    // High, not buried under the breakdown: once this app has actually removed
                    // something, what it removed and what it kept instead is the most valuable
                    // thing on the screen — and the only part of it no other cleaner has.
                    if !history.isEmpty {
                        reclaimedCard
                            .cardEntrance()
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

                    // Before the limits card, because this is weight the app *can* account for
                    // and merely cannot remove — which is a different and more useful thing to
                    // be told than what it cannot see at all.
                    if !model.secondResources.isEmpty {
                        SecondResourcesCardView(resources: model.secondResources)
                            .cardEntrance()
                    }

                    LimitsCardView(cloudOnlyBytes: model.cloudOnlyBytes)
                        .cardEntrance()

                    // Last, so it is nowhere near the part of this screen anybody photographs
                    // for the site — the walk scrolls to it.
                    if AppEnvironment.isUITesting {
                        liveSurfacesEntry
                    }
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
                case .scan: ScanView(container: container, items: model.items, history: history)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    historyEntry
                }
            }
        }
        // Attached to the stack rather than to its root, so the strip stays at the top of
        // History and of anything else pushed on top — the scan is the app's, and a screen you
        // navigated to is not a reason to stop reporting it.
        //
        // `path` is the whole of the "am I already looking at it" question — but only because
        // the scan key below was changed to push by value. It was a view-based
        // `NavigationLink`, which pushes without touching the bound path, so this read said
        // "not on the scan screen" while the scan screen was on top. The strip drew over it,
        // and the UI test caught it on its first run.
        //
        // `.scan` is now the only thing ever appended, and every other push in this app —
        // History, a group, a folder — is still view-based and deliberately leaves the path
        // alone, because the strip belongs on those screens.
        .safeAreaInset(edge: .top, spacing: 0) {
            ScanStripView(
                state: ScanStrip.state(
                    isScanning: scan.isScanning,
                    isPaused: scan.isPaused,
                    progress: scan.progress,
                    isShowingScan: !path.isEmpty
                ),
                // No new navigation: this is the same door the Live Activity and the widget
                // come through, and `onChange(of: pendingLink)` below already knows to replace
                // the path rather than stack a second scan screen on it.
                onTap: { pendingLink = .scan }
            )
        }
        .sheet(isPresented: $showingLiveSurfaces) {
            LiveSurfacePreviewView { showingLiveSurfaces = false }
        }
        // Presented from here rather than from `AppShell` because `model` is here. The last
        // page's whole job is to route the grant through `requestAccess()`, which is the call
        // that updates `access` and reloads the inventory; from `AppShell` the screen would
        // have to raise the alert against a second library instance and leave this one still
        // showing a permission wall over a library it had just been allowed to open.
        //
        // It does not wait for the inventory, and that is deliberate — see the note on
        // `requestAccess(waitingForInventory:)`. The cover's key stays disabled until this
        // returns, so waiting for fifty thousand assets to be enumerated meant the screen sat
        // there dead after the permission had already been answered.
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(
                store: container.onboardingStore,
                onGrantPhotos: { await model.requestAccess(waitingForInventory: false) },
                onFinish: { showingOnboarding = false }
            )
        }
        .task {
            await model.refresh()
            model.beginObservingLibrary()
        }
        .onChange(of: scenePhase) { _, phase in
            // Cheap by contract: `refreshAccess` reads the status and stops there unless it
            // actually moved. See the note on it — this fires on every app switch.
            guard phase == .active else { return }
            Task { await model.refreshAccess() }
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
    /// The Lock Screen and the Dynamic Island cannot be walked to on a simulator, so under test
    /// the app renders those same views itself and the walk photographs them. Nothing here is
    /// reachable in a shipping build.
    ///
    /// In the content rather than the toolbar. It was a toolbar glyph, and a toolbar glyph does
    /// not reach the accessibility tree idb reads: the walk saw an `Image` carrying the SF
    /// Symbol's own name and no button at all, so the one picture anyone gets of the Live
    /// Activity has been missing from `docs/screenshots` for every run since it was written.
    private var liveSurfacesEntry: some View {
        Button {
            showingLiveSurfaces = true
        } label: {
            Label("Live surfaces", systemImage: "iphone.gen3")
        }
        .buttonStyle(.keyQuiet)
        .accessibilityIdentifier("root.livesurfaces")
    }

    /// The receipt, in the content as well as the bar.
    ///
    /// The bar chip is the everyday way in and it stays. But it is a toolbar item, which means
    /// the simulator walk cannot see it — History and the receipt have been missing from the
    /// screenshots for the same reason the live surfaces were — and it is also a small chip in
    /// the corner of a screen that otherwise makes no mention of the one thing this app keeps
    /// that no cleaner does: a record of what it removed and what it kept instead.
    @ViewBuilder
    private var reclaimedCard: some View {
        NavigationLink {
            HistoryView()
        } label: {
            Card("What you have got back", symbolName: "clock.arrow.circlepath", rail: DS.deep) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Readout.bytes(history.totalReclaimedBytes, scale: .title, unitScale: .subheadline, tint: DS.deep)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Text("Every deletion this app has made, with the copy that was kept in each one's place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history.open.card")
    }

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
        }
        .accessibilityLabel("History")
        .accessibilityHint("What this app has scanned and removed")
        .accessibilityIdentifier("history.open")
    }

    private var historyChipTitle: String {
        history.totalReclaimedBytes > 0 ? ByteFormatting.string(history.totalReclaimedBytes) : "History"
    }

    // MARK: - The invitation

    /// The block carrying the ladder the whole product is built on, so the offer on the button
    /// is legible before it is tapped rather than after. It was a dark instrument panel; it is
    /// an elevated card now, and the ladder's own colours carry the weight the darkness used to.
    private var scanEntryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow("The regret ladder", tint: DS.onSlabAccent)

                Text("Find what you can lose least")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(DS.onSlab)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Ranked by what deleting actually costs you — identical copies first, your judgement calls last.")
                    .font(.subheadline)
                    .foregroundStyle(DS.onSlab.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ladderPreview

            // By value, not by view. Both roads to the scan screen — this key and the link the
            // Live Activity carries — now go through `path`, which is what makes "am I already
            // looking at it" a question the stack can answer.
            //
            // It also closes something that was already wrong before the strip existed: a
            // view-based push does not appear in the bound path, so `onChange(of: pendingLink)`
            // resetting the path could not pop a scan screen opened from here, and tapping the
            // Live Activity would have put a second one on top of it.
            NavigationLink(value: DeepLink.scan) {
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

                    Badge(DS.cost(tier), tint: DS.costTint(tier))
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
    let container = AppContainer()

    RootView(container: container)
        .environmentObject(container.history)
}
