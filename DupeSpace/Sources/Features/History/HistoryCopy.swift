import Foundation
import DupeCore

enum HistoryCopy {

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let absolute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func when(_ date: Date, now: Date = Date()) -> String {
        relative.localizedString(for: date, relativeTo: now)
    }

    static func exactly(_ date: Date) -> String {
        absolute.string(from: date)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "under a second" }
        if seconds < 60 { return String(format: "%.0f seconds", seconds) }
        let minutes = Int(seconds / 60)
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// How long is left before a deletion stops being undoable from Recently Deleted.
    static func recoveryWindow(_ record: DeletionRecord, now: Date = Date()) -> String? {
        guard let deadline = record.recoverableUntil, now < deadline else { return nil }
        let days = Int((deadline.timeIntervalSince(now) / 86_400).rounded(.up))
        return days == 1 ? "recoverable for 1 more day" : "recoverable for \(days) more days"
    }
}
