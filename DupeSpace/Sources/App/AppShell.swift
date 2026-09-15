import SwiftUI

/// One screen, no tab bar.
///
/// Space and History were two tabs, which cost every screen in the app the bottom seventy points
/// to a floating pill that was on screen even while someone was choosing what to delete. History
/// is not a mode you work in, it is a thing you go and look at afterwards, so it is a destination
/// off the overview instead — one control, and the content gets the room back.
struct AppShell: View {

    /// Carried, not read: this screen owns no services, but the one below it builds its view
    /// model in `init`, where the environment cannot be reached.
    let container: AppContainer

    @EnvironmentObject private var history: HistoryViewModel
    /// Read here rather than in `RootView`, which has a `scenePhase` handler of its own for the
    /// photo permission. The scan is the app's now, not a screen's, so what happens to it when
    /// the app is put down is decided at the app's level.
    @Environment(\.scenePhase) private var scenePhase
    /// Raised when a link asks for the scan screen; RootView pushes it and clears this.
    @State private var pendingLink: DeepLink?

    var body: some View {
        RootView(container: container, pendingLink: $pendingLink)
            .task {
                await history.load()
            }
            .onOpenURL { url in
                guard let link = DeepLink(url) else { return }
                pendingLink = link
            }
            .onChange(of: scenePhase) { _, phase in
                // Explicitly held and explicitly let go, rather than left running into a
                // suspension nobody asked for. A hold the person chose survives both — see
                // `ScanStore.enterForeground()`.
                switch phase {
                case .background: container.scan.enterBackground()
                case .active: container.scan.enterForeground()
                default: break
                }
            }
    }
}
