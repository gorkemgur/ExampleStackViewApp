import SwiftUI

@main
struct DupeSpaceApp: App {

    @StateObject private var history = HistoryViewModel(store: AppEnvironment.makeHistoryStore())

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(history)
        }
    }
}
