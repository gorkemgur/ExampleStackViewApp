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

    /// One registry, shared: the library that reads granted folders and the screen that
    /// manages them have to agree on what is granted.
    static let folderRegistry: any FolderRegistering = isUITesting
        ? InMemoryFolderRegistry()
        : UserDefaultsFolderRegistry()

    static func makeLibrary() -> MediaLibrary {
        guard !isUITesting else { return StubMediaLibrary.uiTestFixture() }
        return CompositeMediaLibrary(
            photos: PhotoKitMediaLibrary(),
            files: FileMediaLibrary(registry: folderRegistry)
        )
    }

    static func makeAnalyzer() -> any AssetAnalyzing {
        guard !isUITesting else { return StubAssetAnalyzer.uiTestFixture() }
        return CompositeAssetAnalyzer(
            photos: PhotoKitAssetAnalyzer(),
            files: FileAssetAnalyzer(registry: folderRegistry)
        )
    }

    static func makeDeleter() -> MediaDeleting {
        guard !isUITesting else { return StubDeleter() }
        return CompositeDeleter(
            photos: PhotoKitDeleter(),
            files: FileDeleter(registry: folderRegistry)
        )
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
