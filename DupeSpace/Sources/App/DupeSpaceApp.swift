import SwiftUI

@main
struct DupeSpaceApp: App {

    @StateObject private var history = HistoryViewModel(store: AppEnvironment.makeHistoryStore())

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(history)
                .task {
                    // A scan whose app was force-quit leaves its Live Activity on the Lock
                    // Screen, reporting progress that will never move again. Nothing else will
                    // clear it, so the next launch does.
                    AppEnvironment.makeScanActivity()?.clearOrphans()
                }
        }
    }
}
