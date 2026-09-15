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

    /// Makes the stub library report `.notDetermined`, so `AccessCardView` is actually drawn.
    ///
    /// The permission wall is the one screen a UI test could not reach without leaving the
    /// fixtures behind: `-ui-testing` pins the stub at `.authorized`, so the card is never on
    /// screen, and the test written to measure it therefore launched with no flags at all and
    /// leaned on the simulator's real TCC state. That works exactly once per simulator — the
    /// moment anything answers the permission, the card stops being drawn and the test fails
    /// saying the card was missing, which is true and tells you nothing. XCUITest cannot reset
    /// TCC; it can pass a flag. Passed alongside `-ui-testing`, as `-clean-library` is.
    static let unansweredAccessFlag = "-unanswered-access"

    static var isAccessUnanswered: Bool {
        ProcessInfo.processInfo.arguments.contains(unansweredAccessFlag)
    }

    /// Shows the onboarding screen even though `-ui-testing` is on.
    ///
    /// `-ui-testing` has to suppress onboarding, because every UI test and the screenshot walk
    /// launch into what looks like a first run and would stop on its first page. Suppressing it
    /// there would otherwise make this the one screen in the app that is never photographed, so
    /// this flag asks for it back. Passed alongside `-ui-testing`, not instead of it, exactly
    /// as `-clean-library` is.
    static let onboardingFlag = "-onboarding"

    static var isForcingOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains(onboardingFlag)
    }

    /// Makes the fixture scan take long enough to be looked at while it runs.
    ///
    /// A running scan is a state a UI test could not otherwise hold still. The fixture is
    /// twenty-eight items against a stub that answers instantly, so the scan is over before a
    /// query for its Pause key can resolve — measured: the test written for the progress strip
    /// waited twenty seconds for `scan.pause` and the tree it printed was the *results* screen.
    /// Racing it is not a fix; a race that is usually won is a test that fails on a busy
    /// machine and tells you nothing about the app.
    ///
    /// `StubAssetAnalyzer` already takes a `stepDelay` — this only asks for one. Passed
    /// alongside `-ui-testing`, exactly as `-clean-library` and `-unanswered-access` are.
    static let slowScanFlag = "-slow-scan"

    static var isSlowScan: Bool {
        ProcessInfo.processInfo.arguments.contains(slowScanFlag)
    }

    /// A library with enough near-duplicates in one rung that the list has to fold some away.
    ///
    /// The ordinary fixture is twenty-eight items and its biggest rung is four groups, so the
    /// row that offers the rest of a long rung is never drawn and the only proof that truncation
    /// works at all was a unit test on the arithmetic. This adds twelve pairs of near-identical
    /// photographs — seven bits apart, no burst identifier between them, so they land on the
    /// bottom rung exactly as a real library's similar shots do.
    ///
    /// Passed alongside `-ui-testing`, as `-clean-library` and `-slow-scan` are.
    static let crowdedLibraryFlag = "-crowded-library"

    static var isCrowdedLibrary: Bool {
        ProcessInfo.processInfo.arguments.contains(crowdedLibraryFlag)
    }

    /// Long enough to reach a control on a loaded simulator, short enough that a test which
    /// cancels rather than waits pays almost none of it. Four reads at a time over twenty-eight
    /// items is roughly seven steps a stage, so this buys about twelve seconds of scanning.
    private static let slowScanStep = Duration.milliseconds(600)

    /// One store, shared: the gate that decides whether to present the screen and the screen
    /// that marks it seen have to agree on what has been seen. Calling this twice would make two
    /// stores and let them disagree, so `AppContainer` calls it once and owns the answer.
    ///
    /// In memory under test, so a walk that reaches the end of the sequence does not leave a
    /// "seen" flag in the simulator's defaults for the next run to trip over.
    static func makeOnboardingStore() -> any OnboardingStoring {
        isUITesting ? InMemoryOnboardingStore() : UserDefaultsOnboardingStore()
    }

    /// One registry, shared: the library that reads granted folders and the screen that
    /// manages them have to agree on what is granted. Held by `AppContainer` and passed into
    /// every service below that reads folders — which is why they take it rather than reach for
    /// it, because a factory that reached for it would be reaching for a second one.
    static func makeFolderRegistry() -> any FolderRegistering {
        isUITesting ? InMemoryFolderRegistry() : UserDefaultsFolderRegistry()
    }

    static func makeLibrary(registry: any FolderRegistering) -> MediaLibrary {
        guard !isUITesting else {
            if isAccessUnanswered { return StubMediaLibrary.unansweredFixture() }
            return isCrowdedLibrary
                ? StubMediaLibrary.crowdedFixture()
                : StubMediaLibrary.uiTestFixture()
        }
        return CompositeMediaLibrary(
            photos: PhotoKitMediaLibrary(),
            files: FileMediaLibrary(registry: registry)
        )
    }

    /// Kept between launches so a second scan does not re-read a library that has not changed.
    /// UI tests get a fresh one so their assertions describe this run's work.
    ///
    /// One per launch, held by `AppContainer`: the analyzer writes into it and the scan screen
    /// reports how much of the work it saved, and two caches would make that figure a fiction.
    static func makeFingerprintCache() -> FileFingerprintCache {
        isUITesting
            ? FileFingerprintCache(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("ui-test-fingerprints-\(UUID().uuidString).bin")
            )
            : FileFingerprintCache()
    }

    static func makeAnalyzer(
        registry: any FolderRegistering,
        cache: FileFingerprintCache
    ) -> any AssetAnalyzing {
        let step = isSlowScan ? slowScanStep : Duration.zero
        let base: any AssetAnalyzing = isUITesting
            ? (isCleanLibrary
                ? StubAssetAnalyzer.cleanFixture()
                : (isCrowdedLibrary
                    ? StubAssetAnalyzer.crowdedFixture(stepDelay: step)
                    : StubAssetAnalyzer.uiTestFixture(stepDelay: step)))
            : CompositeAssetAnalyzer(
                photos: PhotoKitAssetAnalyzer(),
                files: FileAssetAnalyzer(registry: registry)
            )
        return CachingAnalyzer(base: base, cache: cache)
    }

    /// No Live Activity under UI test: a simulator shows none, and a run's assertions should
    /// describe the app's own screens rather than a surface that cannot appear.
    static func makeScanActivity() -> (any ScanActivityPresenting)? {
        isUITesting ? nil : LiveScanActivityController()
    }

    static func makeChangeObserver() -> any LibraryChangeObserving {
        isUITesting ? StubLibraryChangeObserver() : PhotoLibraryChangeObserver()
    }

    static func makeDeleter(registry: any FolderRegistering) -> MediaDeleting {
        // No delay. There used to be 420 milliseconds a step here, for one reason: the walk
        // photographed the deletion while it ran, and a stub that finishes in a frame leaves
        // nothing to photograph. That walk was deleted with the rest of the recordings, so
        // what is left is every UI test that deletes anything paying three seconds for a film
        // nobody makes.
        guard !isUITesting else { return StubDeleter(stepDelay: .zero) }
        return CompositeDeleter(
            photos: PhotoKitDeleter(),
            files: FileDeleter(registry: registry)
        )
    }

    @MainActor
    static func makeExporter(registry: any FolderRegistering) -> OriginalExporting {
        isUITesting ? StubOriginalExporter() : FileSystemOriginalExporter(registry: registry)
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
