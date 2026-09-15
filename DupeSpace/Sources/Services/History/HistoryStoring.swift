import Foundation
import DupeCore

protocol HistoryStoring: Sendable {
    func load() async -> HistoryLog
    func save(_ log: HistoryLog) async
}

/// Keeps the receipt in the app's own container as plain JSON.
///
/// A corrupt or absent file is treated as "no history" rather than as an error worth showing:
/// the log is a record of what happened, and failing to read it must never stop the user from
/// doing the thing it is a record of.
final class FileHistoryStore: HistoryStoring {

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = base.appendingPathComponent("DupeSpace", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("history.json")
        }
    }

    func load() async -> HistoryLog {
        let url = fileURL
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return HistoryLog() }
            return (try? JSONDecoder().decode(HistoryLog.self, from: data)) ?? HistoryLog()
        }.value
    }

    func save(_ log: HistoryLog) async {
        let url = fileURL
        await Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(log) else { return }
            try? data.write(to: url, options: .atomic)
        }.value
    }
}

/// For tests and previews.
final class InMemoryHistoryStore: HistoryStoring, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: HistoryLog
    private var _saveCount = 0

    init(log: HistoryLog = HistoryLog()) {
        storage = log
    }

    var saveCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _saveCount
    }

    func load() async -> HistoryLog {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func save(_ log: HistoryLog) async {
        lock.lock(); defer { lock.unlock() }
        storage = log
        _saveCount += 1
    }
}
