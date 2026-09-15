import Combine
import Foundation
import DupeCore

/// The app's services, built once and handed down.
///
/// `AppEnvironment` still decides *which* service a launch gets — the flags are its work and they
/// stay there. What moved here is *ownership*. Three `static let`s used to be the only shared
/// instances in the app and every other service was built by whichever screen happened to need
/// one, which cost two things that were invisible from any single file: a review screen built its
/// own thumbnail loader and therefore its own `NSCache`, so everything it had fetched was thrown
/// away when the screen closed; and `makeScanActivity()` was called twice, once by the launch that
/// clears an orphaned Live Activity and once by the scan that starts one, so the object doing the
/// clearing was never the object that had published.
///
/// Handed down through initialisers rather than through the environment. Three screens build their
/// view models inside `init` — that is what keeps them to a single construction, because
/// `@StateObject`'s `wrappedValue` is an autoclosure — and `@Environment` cannot be read there. An
/// `EnvironmentKey` would need a default value, and a default value is a second container that any
/// view handed no container reaches silently: two folder registries, two fingerprint caches, and
/// nothing on fire. An initialiser parameter that is missing does not compile.
///
/// `ObservableObject` with nothing published, for one reason: `@StateObject` takes its value as an
/// autoclosure, so the container is constructed exactly once for the life of the app. Nothing here
/// ever changes, so there is nothing to observe.
@MainActor
final class AppContainer: ObservableObject {

    /// Built first and passed into the four services that read granted folders. They have to be
    /// looking at the same registry as the screen that grants them, which is the whole reason this
    /// was a `static let` before it was a property.
    let folderRegistry: any FolderRegistering

    /// Shared for the same reason: the analyzer writes fingerprints into it and the scan screen
    /// reports how many of them were reused. Two caches would make that number a fiction.
    let fingerprintCache: FileFingerprintCache

    let onboardingStore: any OnboardingStoring
    let library: MediaLibrary
    let analyzer: any AssetAnalyzing
    let changeObserver: any LibraryChangeObserving
    let deleter: MediaDeleting
    let exporter: OriginalExporting
    let thumbnails: any ThumbnailLoading

    /// Optional because a UI test gets none — a simulator presents no Live Activity, and a run's
    /// assertions should describe the app's own screens.
    let scanActivity: (any ScanActivityPresenting)?

    /// Owned here, observed through `environmentObject`. Ownership and observation are different
    /// questions: the container answers who built it and keeps it alive, SwiftUI's environment
    /// answers which views redraw when it changes.
    let history: HistoryViewModel

    /// The scan, for as long as the app runs.
    ///
    /// Here rather than inside `ScanView` because a scan of a real library takes minutes, and a
    /// `@StateObject` on a pushed screen dies the moment somebody backs out to look at something
    /// — which is why that screen also had to cancel the scan on its way out. Owned here, going
    /// back is just going back, and the result is still there when they return.
    let scan: ScanStore

    init() {
        let registry = AppEnvironment.makeFolderRegistry()
        let cache = AppEnvironment.makeFingerprintCache()

        folderRegistry = registry
        fingerprintCache = cache
        onboardingStore = AppEnvironment.makeOnboardingStore()
        library = AppEnvironment.makeLibrary(registry: registry)
        let analyzer = AppEnvironment.makeAnalyzer(registry: registry, cache: cache)
        self.analyzer = analyzer
        changeObserver = AppEnvironment.makeChangeObserver()
        deleter = AppEnvironment.makeDeleter(registry: registry)
        exporter = AppEnvironment.makeExporter(registry: registry)
        thumbnails = AppEnvironment.makeThumbnailLoader()
        let scanActivity = AppEnvironment.makeScanActivity()
        self.scanActivity = scanActivity

        let history = HistoryViewModel(store: AppEnvironment.makeHistoryStore())
        self.history = history
        scan = ScanStore(
            manager: ScanManager(analyzer: analyzer, cache: cache),
            history: history,
            activity: scanActivity
        )
    }
}
