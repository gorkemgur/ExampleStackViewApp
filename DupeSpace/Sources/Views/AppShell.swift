import SwiftUI

struct AppShell: View {

    @EnvironmentObject private var history: HistoryViewModel
    @State private var selection: Tab = .space

    enum Tab: Hashable {
        case space
        case history
    }

    var body: some View {
        TabView(selection: $selection) {
            RootView()
                .tag(Tab.space)
                .tabItem {
                    Label("Space", systemImage: "internaldrive")
                }

            HistoryView()
                .tag(Tab.history)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .badge(history.totalItemsDeleted)
        }
        .task {
            await history.load()
        }
    }
}
