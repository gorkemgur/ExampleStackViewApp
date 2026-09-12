import SwiftUI

/// One screen, no tab bar.
///
/// Space and History were two tabs, which cost every screen in the app the bottom seventy points
/// to a floating pill that was on screen even while someone was choosing what to delete. History
/// is not a mode you work in, it is a thing you go and look at afterwards, so it is a destination
/// off the overview instead — one control, and the content gets the room back.
struct AppShell: View {

    @EnvironmentObject private var history: HistoryViewModel
    /// Raised when a link asks for the scan screen; RootView pushes it and clears this.
    @State private var pendingLink: DeepLink?

    var body: some View {
        RootView(pendingLink: $pendingLink)
            .task {
                await history.load()
            }
            .onOpenURL { url in
                guard let link = DeepLink(url) else { return }
                pendingLink = link
            }
    }
}
