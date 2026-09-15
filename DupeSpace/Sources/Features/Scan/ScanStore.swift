import Combine
import Foundation
import DupeCore

/// The scan as the app knows it: what to draw, what to write down, what to put on the Lock
/// Screen.
///
/// Owned by `AppContainer` and alive for as long as the app is, which is the point of it. This
/// used to be a `@StateObject` inside `ScanView`, so backing out of the scan screen destroyed a
/// scan that might have been forty minutes in — and the screen cancelled it on the way out,
/// because leaving it running with nowhere to report to was the only other option.
///
/// Everything here runs on the main actor and every side effect that reaches the rest of the app
/// lives here rather than in `ScanManager`: `HistoryViewModel` and the Live Activity controller
/// are both main-actor types, so an actor could only reach them by hopping back, and the hop is
/// the thing this split exists to avoid.
@MainActor
final class ScanStore: ObservableObject {

    @Published private(set) var isScanning = false
    @Published private(set) var progress: ScanProgress?
    @Published private(set) var result: ScanResult?
    @Published private(set) var failure: String?
    @Published private(set) var wasCancelled = false
    @Published private(set) var isPaused = false

    /// How alike counts as a duplicate. The largest judgement in the app, and now the user's.
    @Published var strictness: ScanStrictness {
        didSet { Self.remember(strictness) }
    }

    private let manager: ScanManager
    /// Set only by tests that need a fixed configuration; otherwise the strictness decides.
    private let configurationOverride: ScanConfiguration?
    private weak var history: (any HistoryRecording)?
    private let activity: (any ScanActivityPresenting)?

    /// Whether the hold currently in force is the person's, as opposed to the one the app takes
    /// when it is put into the background.
    ///
    /// Without this the two are indistinguishable, and coming back to the front would resume a
    /// scan somebody had deliberately held — the app overruling them for no reason they could
    /// see.
    private var isHeldByUser = false
    private var startedAt = Date()
    private var itemCount = 0

    init(
        manager: ScanManager,
        configuration: ScanConfiguration? = nil,
        history: (any HistoryRecording)? = nil,
        activity: (any ScanActivityPresenting)? = nil
    ) {
        self.manager = manager
        self.configurationOverride = configuration
        self.strictness = Self.remembered()
        self.history = history
        self.activity = activity
    }

    func start(items: [MediaItem]) {
        guard !isScanning else { return }

        isScanning = true
        wasCancelled = false
        isPaused = false
        isHeldByUser = false
        failure = nil
        result = nil
        progress = ScanProgress(stage: .bucketing, completed: 0, total: items.count)
        startedAt = Date()
        itemCount = items.count

        activity?.start(libraryItemCount: items.count, state: liveState(phase: .scanning))

        let events = manager.start(
            items: items,
            configuration: configurationOverride ?? strictness.configuration
        )

        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.apply(event, itemsScanned: items.count)
            }
            // The stream ends after the engine has flushed the cache, not when it stopped
            // reading — so a scan is still "running" while the fingerprints it earned are
            // being written down.
            self?.isScanning = false
        }
    }

    // MARK: - Controls
    //
    // Straight through to the manager, synchronously. See the note on `ScanPauseGate`: these
    // are button handlers, and a control that takes a hop to reach the gate can arrive after
    // the one pressed later.

    func pause() {
        guard isScanning, !isPaused else { return }
        isHeldByUser = true
        hold()
    }

    func resume() {
        guard isPaused else { return }
        isHeldByUser = false
        release()
    }

    func cancel() {
        manager.cancel()
        isPaused = false
        isHeldByUser = false
    }

    /// The app is being put down. Hold the scan rather than leave it reading the library from
    /// the background, where iOS will suspend it mid-read anyway and the progress on the Lock
    /// Screen would stop moving with nothing to say why.
    func enterBackground() {
        guard isScanning, !isPaused else { return }
        hold()
    }

    /// Back to the front. Resumes only what this type held.
    func enterForeground() {
        guard isScanning, isPaused, !isHeldByUser else { return }
        release()
    }

    private func hold() {
        isPaused = true
        manager.pause()
        activity?.update(liveState(phase: .paused))
    }

    private func release() {
        isPaused = false
        manager.resume()
        activity?.update(liveState(phase: .scanning))
    }

    // MARK: - Reading the engine

    private func apply(_ event: ScanEvent, itemsScanned: Int) {
        switch event {
        case let .progress(update):
            progress = update
            activity?.update(liveState(phase: isPaused ? .paused : .scanning))

        case let .finished(scan):
            result = scan
            WidgetPublisher.publish(scan: scan)
            activity?.finish(
                liveState(
                    phase: .finished,
                    candidateCount: scan.candidates.count,
                    reclaimableBytes: scan.reclaimableBytes
                )
            )
            history?.record(
                scan: HistoryBuilder.scanRecord(
                    result: scan,
                    itemsScanned: itemsScanned,
                    startedAt: startedAt,
                    finishedAt: Date()
                )
            )

        case .cancelled:
            wasCancelled = true
            activity?.finish(liveState(phase: .cancelled))

        case let .failed(message):
            failure = message
            activity?.finish(liveState(phase: .failed))
        }
    }

    // MARK: - Remembering the choice

    private static let strictnessKey = "scan.strictness"

    private static func remembered() -> ScanStrictness {
        // Never under test. The unit bundle is hosted by the app, so a unit test that touches
        // `strictness` writes the same defaults every later UI test launches with — and a UI
        // test that scans at a strictness it did not choose is a test of something else.
        guard !AppEnvironment.isUITesting else { return .balanced }
        guard
            let raw = UserDefaults.standard.object(forKey: strictnessKey) as? Int,
            let stored = ScanStrictness(rawValue: raw)
        else {
            return .balanced
        }
        return stored
    }

    private static func remember(_ strictness: ScanStrictness) {
        UserDefaults.standard.set(strictness.rawValue, forKey: strictnessKey)
    }

    /// The running scan in the shape the Lock Screen and the Dynamic Island read.
    ///
    /// Totals stay at zero until the scan finishes, because until the planning stage has run
    /// there is no honest number to show: an item is only a candidate once something else is
    /// known to be a better copy of it.
    private func liveState(
        phase: LiveScanState.Phase,
        candidateCount: Int = 0,
        reclaimableBytes: Int64 = 0
    ) -> LiveScanState {
        LiveScanState(
            phase: phase,
            stage: progress?.stage ?? .bucketing,
            completed: progress?.completed ?? 0,
            total: progress?.total ?? itemCount,
            candidateCount: candidateCount,
            reclaimableBytes: reclaimableBytes,
            startedAt: startedAt
        )
    }
}
