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
        let onProgress: @Sendable (ScanProgress) -> Void = { [weak self] update in
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
                    await cache.flush()
                }
            } catch is CancellationError {
                self.wasCancelled = true
                self.activity?.finish(self.liveState(phase: .cancelled))
            } catch {
                self.failure = error.localizedDescription
                self.activity?.finish(self.liveState(phase: .failed))
            }
            self.isScanning = false
        }
    }

    func pause() {
        guard isScanning, !isPaused else { return }
        isPaused = true
        activity?.update(liveState(phase: .paused))
        let gate = self.gate
        Task { await gate.pause() }
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        activity?.update(liveState(phase: .scanning))
        let gate = self.gate
        Task { await gate.resume() }
    }

    func cancel() {
        // Released first: a held scan that is cancelled has to be let go before it can notice.
        let gate = self.gate
        Task { await gate.resume() }
        isPaused = false
        task?.cancel()
        task = nil
    }

    // MARK: - Remembering the choice

    private static let strictnessKey = "scan.strictness"

    private static func remembered() -> ScanStrictness {
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
