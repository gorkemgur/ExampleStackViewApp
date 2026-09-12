import Foundation

/// Byte counts as people read them.
///
/// Lives in the shared package because the app and the widget must never disagree about what
/// the same number looks like.
public enum ByteText {

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        // Without this the formatter writes "Zero KB", which reads as a formatting bug rather
        // than as a measurement.
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static let compactFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.allowsNonnumericFormatting = false
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()

    public static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: max(bytes, 0))
    }

    /// For places with no room for "MB" next to a three-digit number.
    public static func compact(_ bytes: Int64) -> String {
        compactFormatter.string(fromByteCount: max(bytes, 0))
    }
}
