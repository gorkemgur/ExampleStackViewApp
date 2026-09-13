import Foundation
import UIKit
import DupeCore

/// Picks the real services or the deterministic fixtures.
enum AppEnvironment {

    /// Set by the UI test bundle. Keeps the permission alert — which nothing can tap on a CI
    /// machine — out of the way, and pins the library to a known fixture.
    static let uiTestingFlag = "-ui-testing"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingFlag)
    }

    /// The same fixture library with nothing in it that matches anything.
    ///
    /// A tidy library is the state this app is least often looked at in and the one a new user
    /// is most likely to be in. Passed alongside `-ui-testing`, not instead of it: the library
    /// and the storage figures stay exactly as they are, and only the analyzer changes, so
    /// every screen is the one people actually see rather than a blanked-out shell.
    static let cleanLibraryFlag = "-clean-library"

    static var isCleanLibrary: Bool {
        ProcessInfo.processInfo.arguments.contains(cleanLibraryFlag)
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
            ? (isCleanLibrary ? StubAssetAnalyzer.cleanFixture() : StubAssetAnalyzer.uiTestFixture())
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
        // No delay. There used to be 420 milliseconds a step here, for one reason: the walk
        // photographed the deletion while it ran, and a stub that finishes in a frame leaves
        // nothing to photograph. That walk was deleted with the rest of the recordings, so
        // what is left is every UI test that deletes anything paying three seconds for a film
        // nobody makes.
        guard !isUITesting else { return StubDeleter(stepDelay: .zero) }
        return CompositeDeleter(
            photos: PhotoKitDeleter(),
            files: FileDeleter(registry: folderRegistry)
        )
    }

    @MainActor
    static func makeExporter() -> OriginalExporting {
        isUITesting ? StubOriginalExporter() : FileSystemOriginalExporter(registry: folderRegistry)
    }

    static func makeThumbnailLoader() -> ThumbnailLoading {
        isUITesting ? StubThumbnailLoader() : PhotoKitThumbnailLoader(scale: UIScreen.main.scale)
    }

    /// UI tests start from a clean slate so an assertion about "one deletion in the history"
    /// means this run's deletion, not one left behind by an earlier run on the same simulator.
    static func makeHistoryStore() -> any HistoryStoring {
        isUITesting ? InMemoryHistoryStore() : FileHistoryStore()
    }
}
