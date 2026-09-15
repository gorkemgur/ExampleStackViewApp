import Combine
import Foundation
import DupeCore

@MainActor
final class ScanViewModel: ObservableObject {

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

    private let analyzer: any AssetAnalyzing
    /// Set only by tests that need a fixed configuration; otherwise the strictness decides.
    private let configurationOverride: ScanConfiguration?
    private weak var history: (any HistoryRecording)?
    private var task: Task<Void, Never>?
    private var gate = ScanPauseGate()
    private let cache: FileFingerprintCache?
    private let activity: (any ScanActivityPresenting)?
    private var startedAt = Date()
    private var itemCount = 0

    init(
        analyzer: any AssetAnalyzing,
        configuration: ScanConfiguration? = nil,
        history: (any HistoryRecording)? = nil,
        cache: FileFingerprintCache? = nil,
        activity: (any ScanActivityPresenting)? = nil
    ) {
        self.analyzer = analyzer
        self.configurationOverride = configuration
        self.strictness = Self.remembered()
        self.history = history
        self.cache = cache
        self.activity = activity
    }

    var hasFinished: Bool { result != nil }

    func start(items: [MediaItem]) {
        guard !isScanning else { return }

        isScanning = true
        wasCancelled = false
        isPaused = false
        failure = nil
        result = nil
        progress = ScanProgress(stage: .bucketing, completed: 0, total: items.count)

        gate = ScanPauseGate()
        let pipeline = ScanPipeline(
            analyzer: analyzer,
            configuration: configurationOverride ?? strictness.configuration,
            pause: gate
        )
        // Throttled at the source, not at the sink.
        //
        // The pipeline reports after every completed item, so a fifty-thousand-photo library
        // used to enqueue fifty thousand `Task { @MainActor in }` hops, each writing a
        // `@Published` property and so invalidating the whole scan screen — while the pipeline
        // was already saturating the device's I/O. The main actor spent the scan servicing
        // updates nobody could read, which is exactly when the pause and cancel buttons stop
        // answering. `LiveScanPublishPolicy` rationed the Lock Screen; nothing rationed this.
        //
        // A change is worth a hop when it changes the stage or moves the visible percentage.
        // Everything else is the same frame drawn again.
        let throttle = ProgressThrottle()
        let onProgress: @Sendable (ScanProgress) -> Void = { [weak self] update in
            guard throttle.shouldPublish(update) else { return }
            Task { @MainActor in
                guard let self else { return }
                self.progress = update
                self.activity?.update(self.liveState(phase: self.isPaused ? .paused : .scanning))
            }
        }

        let startedAt = Date()
        self.startedAt = startedAt
        self.itemCount = items.count
        activity?.start(
            libraryItemCount: items.count,
            state: liveState(phase: .scanning)
        )

        task = Task {
            do {
                let scan = try await pipeline.run(items: items, progress: onProgress)
                self.result = scan
                WidgetPublisher.publish(scan: scan)
                self.activity?.finish(
                    self.liveState(
                        phase: .finished,
                        candidateCount: scan.candidates.count,
                        reclaimableBytes: scan.reclaimableBytes
                    )
                )
                self.history?.record(
                    scan: HistoryBuilder.scanRecord(
                        result: scan,
                        itemsScanned: items.count,
                        startedAt: startedAt,
                        finishedAt: Date()
                    )
                )

                // Written once the work is done rather than after every fingerprint: fifty
                // thousand writes of the same file would cost more than the cache saves. The
                // library's own ids bound it, so items that have gone are forgotten.
                if let cache = self.cache {
                    await cache.prune(keeping: Set(items.map(\.id)))
                }
            } catch is CancellationError {
                self.wasCancelled = true
                self.activity?.finish(self.liveState(phase: .cancelled))
            } catch {
                self.failure = error.localizedDescription
                self.activity?.finish(self.liveState(phase: .failed))
            }

            // Flushed on every ending, not just the happy one. It used to sit inside the
            // success branch, so cancelling a forty-minute first scan at ninety-five per cent
            // threw away every fingerprint it had computed and the next launch started from
            // nothing — the exact opposite of what a scan you are allowed to stop is for.
            // Every record in there was earned by reading a file; none of it is invalidated by
            // the scan ending early.
            await self.cache?.flush()

            self.isScanning = false
        }
    }

    // The gate is set synchronously — see the note on `ScanPauseGate`. Wrapping these in
    // `Task { await … }` meant a quick pause-then-resume could reach the gate the other way
    // round and hang the scan behind a hold the screen said was not there.
    func pause() {
        guard isScanning, !isPaused else { return }
        isPaused = true
        gate.pause()
        activity?.update(liveState(phase: .paused))
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        gate.resume()
        activity?.update(liveState(phase: .scanning))
    }

    func cancel() {
        // Released first, and now genuinely first: a held scan that is cancelled has to be let
        // go before it can notice.
        gate.resume()
        isPaused = false
        task?.cancel()
        task = nil
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

/// Decides which of the pipeline's per-item progress reports are worth waking the main actor
/// for.
///
/// Called from whatever thread the pipeline happens to be on, once per finished item, so it
/// holds its state under a lock rather than an actor: an actor here would put back the hop this
/// type exists to remove.
///
/// The rule is what the screen can actually show. A stage change always goes through, because
/// the label is the largest thing on the screen. Otherwise the percentage has to move — at one
/// decimal place, which is finer than the bar can draw but coarse enough that a fifty-thousand
/// item stage sends about a thousand updates instead of fifty thousand.
final class ProgressThrottle: @unchecked Sendable {

    private let lock = NSLock()
    private var lastStage: ScanProgress.Stage?
    private var lastTick: Int = -1
    /// The highest `completed` allowed through for the current stage.
    ///
    /// Every accepted update starts its own task on the main actor, and two independently
    /// created tasks have no order between them — so the bar could tick backwards under load,
    /// which is the "looks stuck" symptom this throttle exists to remove. Anything not
    /// strictly newer than what has already gone through is dropped here, where the ordering
    /// is still knowable.
    private var lastCompleted: Int = -1

    func shouldPublish(_ update: ScanProgress) -> Bool {
        let tick = update.total > 0
            ? Int((Double(update.completed) / Double(update.total)) * 1_000)
            : Int(update.completed)

        lock.lock()
        defer { lock.unlock() }

        // The end of a stage always goes through, so the bar is never left short of the mark
        // it reached.
        let isStageChange = update.stage != lastStage
        let isComplete = update.total > 0 && update.completed >= update.total
        guard isStageChange || isComplete || tick != lastTick else { return false }
        // A new stage resets the count, so "newer" only means anything within one stage.
        guard isStageChange || update.completed > lastCompleted else { return false }

        lastStage = update.stage
        lastTick = tick
        lastCompleted = update.completed
        return true
    }
}
