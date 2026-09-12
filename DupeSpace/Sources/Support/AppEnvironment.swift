import Foundation
import DupeCore

/// Picks the real services or the deterministic fixtures.
enum AppEnvironment {

    /// Set by the UI test bundle. Keeps the permission alert — which nothing can tap on a CI
    /// machine — out of the way, and pins the library to a known fixture.
    static let uiTestingFlag = "-ui-testing"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingFlag)
    }

    static func makeLibrary() -> MediaLibrary {
        isUITesting ? StubMediaLibrary.uiTestFixture() : PhotoKitMediaLibrary()
    }

    static func makeAnalyzer() -> any AssetAnalyzing {
        isUITesting ? StubAssetAnalyzer.uiTestFixture() : PhotoKitAssetAnalyzer()
    }

    static func makeDeleter() -> MediaDeleting {
        isUITesting ? StubDeleter() : PhotoKitDeleter()
    }

    static func makeThumbnailLoader() -> ThumbnailLoading {
        isUITesting ? StubThumbnailLoader() : PhotoKitThumbnailLoader()
    }

    /// UI tests start from a clean slate so an assertion about "one deletion in the history"
    /// means this run's deletion, not one left behind by an earlier run on the same simulator.
    static func makeHistoryStore() -> any HistoryStoring {
        isUITesting ? InMemoryHistoryStore() : FileHistoryStore()
    }
}
