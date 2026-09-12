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

    /// Kept between launches so a second scan does not re-read a library that has not changed.
    /// UI tests get a fresh one so their assertions describe this run's work.
    static let fingerprintCache: FileFingerprintCache = isUITesting
        ? FileFingerprintCache(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ui-test-fingerprints-\(UUID().uuidString).json")
        )
        : FileFingerprintCache()

    static func makeAnalyzer() -> any AssetAnalyzing {
        let base: any AssetAnalyzing = isUITesting
            ? StubAssetAnalyzer.uiTestFixture()
            : CompositeAssetAnalyzer(
                photos: PhotoKitAssetAnalyzer(),
                files: FileAssetAnalyzer(registry: folderRegistry)
            )
        return CachingAnalyzer(base: base, cache: fingerprintCache)
    }

    /// No Live Activity under UI test: a simulator shows none, and a run's assertions should
    /// describe the app's own screens rather than a surface that cannot appear.
    static func makeScanActivity() -> (any ScanActivityPresenting)? {
        isUITesting ? nil : LiveScanActivityController()
    }

    static func makeChangeObserver() -> any LibraryChangeObserving {
        isUITesting ? StubLibraryChangeObserver() : PhotoLibraryChangeObserver()
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
