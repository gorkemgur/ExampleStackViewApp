import SwiftUI

@main
struct DupeSpaceApp: App {

    /// Every service the app owns, built here and nowhere else.
    ///
    /// `@StateObject` rather than a stored property because its value is an autoclosure: the
    /// container is constructed exactly once, whatever SwiftUI chooses to do with this struct.
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            AppShell(container: container)
                .environmentObject(container.history)
                .task {
                    // A scan whose app was force-quit leaves its Live Activity on the Lock
                    // Screen, reporting progress that will never move again. Nothing else will
                    // clear it, so the next launch does — through the same controller the next
                    // scan will publish on, which was not true while this line built its own.
                    container.scanActivity?.clearOrphans()
                }
        }
    }
}
