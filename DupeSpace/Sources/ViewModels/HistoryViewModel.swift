import Combine
import Foundation
import DupeCore

/// What the scan and review screens need in order to leave a receipt behind.
@MainActor
protocol HistoryRecording: AnyObject {
    func record(scan: ScanRecord)
    func record(deletion: DeletionRecord)
}

@MainActor
final class HistoryViewModel: ObservableObject, HistoryRecording {

    @Published private(set) var log = HistoryLog()
    @Published private(set) var hasLoaded = false

    private let store: any HistoryStoring

    init(store: any HistoryStoring) {
        self.store = store
    }

    var timeline: [HistoryEntry] { log.timeline }
    var isEmpty: Bool { log.isEmpty }
    var totalReclaimedBytes: Int64 { log.totalReclaimedBytes }
    var totalItemsDeleted: Int { log.totalItemsDeleted }

    func recoverableDeletions(at date: Date = Date()) -> [DeletionRecord] {
        log.recoverableDeletions(at: date)
    }

    func load() async {
        guard !hasLoaded else { return }
        log = await store.load()
        hasLoaded = true
    }

    func record(scan: ScanRecord) {
        log.record(scan)
        persist()
    }

    func record(deletion: DeletionRecord) {
        log.record(deletion)
        persist()
    }

    func clear() {
        log.clear()
        persist()
    }

    private func persist() {
        let snapshot = log
        let store = self.store
        Task.detached(priority: .utility) {
            await store.save(snapshot)
        }
    }
}
