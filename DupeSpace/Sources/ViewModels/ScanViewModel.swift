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

    private let analyzer: any AssetAnalyzing
    private let configuration: ScanConfiguration
    private weak var history: (any HistoryRecording)?
    private var task: Task<Void, Never>?
    private var gate = ScanPauseGate()
    private let cache: FileFingerprintCache?

    init(
        analyzer: any AssetAnalyzing,
        configuration: ScanConfiguration = .default,
        history: (any HistoryRecording)? = nil,
        cache: FileFingerprintCache? = nil
    ) {
        self.analyzer = analyzer
        self.configuration = configuration
        self.history = history
        self.cache = cache
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
        let pipeline = ScanPipeline(analyzer: analyzer, configuration: configuration, pause: gate)
        let onProgress: @Sendable (ScanProgress) -> Void = { [weak self] update in
            Task { @MainActor in self?.progress = update }
        }

        let startedAt = Date()

        task = Task {
            do {
                let scan = try await pipeline.run(items: items, progress: onProgress)
                self.result = scan
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
            } catch {
                self.failure = error.localizedDescription
            }
            self.isScanning = false
        }
    }

    func pause() {
        guard isScanning, !isPaused else { return }
        isPaused = true
        let gate = self.gate
        Task { await gate.pause() }
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
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
}
