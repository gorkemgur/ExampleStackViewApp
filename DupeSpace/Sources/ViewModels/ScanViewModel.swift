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

    private let analyzer: any AssetAnalyzing
    private let configuration: ScanConfiguration
    private var task: Task<Void, Never>?

    init(analyzer: any AssetAnalyzing, configuration: ScanConfiguration = .default) {
        self.analyzer = analyzer
        self.configuration = configuration
    }

    var hasFinished: Bool { result != nil }

    func start(items: [MediaItem]) {
        guard !isScanning else { return }

        isScanning = true
        wasCancelled = false
        failure = nil
        result = nil
        progress = ScanProgress(stage: .bucketing, completed: 0, total: items.count)

        let pipeline = ScanPipeline(analyzer: analyzer, configuration: configuration)
        let onProgress: @Sendable (ScanProgress) -> Void = { [weak self] update in
            Task { @MainActor in self?.progress = update }
        }

        task = Task {
            do {
                let scan = try await pipeline.run(items: items, progress: onProgress)
                self.result = scan
            } catch is CancellationError {
                self.wasCancelled = true
            } catch {
                self.failure = error.localizedDescription
            }
            self.isScanning = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
