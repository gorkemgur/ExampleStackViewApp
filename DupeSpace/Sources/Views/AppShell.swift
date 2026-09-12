import SwiftUI

struct AppShell: View {

    @EnvironmentObject private var history: HistoryViewModel
    @State private var selection: Tab = .space
    /// Raised when a link asks for the scan screen; RootView pushes it and clears this.
    @State private var pendingLink: DeepLink?

    enum Tab: Hashable {
        case space
        case history
    }

    var body: some View {
        TabView(selection: $selection) {
            RootView(pendingLink: $pendingLink)
                .tag(Tab.space)
                .tabItem {
                    Label("Space", systemImage: "internaldrive")
                }

            HistoryView()
                .tag(Tab.history)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
        .task {
            await history.load()
        }
        .onOpenURL { url in
            guard let link = DeepLink(url) else { return }
            selection = .space
            pendingLink = link
        }
    }
}
