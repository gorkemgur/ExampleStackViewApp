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

    /// Three or four glyphs, for the inside of a gauge ring and the Dynamic Island's compact
    /// slots — places where "44.22 GB" is not a small label, it is a clipped one.
    ///
    /// The unit is a single letter and the rounding gets coarser as the number gets longer, so
    /// the result is never wider than four characters at any size a phone can hold.
    public static func tight(_ bytes: Int64) -> String {
        let value = Double(max(bytes, 0))

        for (unit, scale) in [("T", 1_000_000_000_000.0), ("G", 1_000_000_000.0)] {
            let scaled = value / scale
            // 9.95 and 0.995 rather than 10 and 1: the rounding that formats the number has to
            // agree with the comparison that picked the format, or 999.9 MB prints as "1000M".
            if scaled >= 9.95 { return "\(Int(scaled.rounded()))\(unit)" }
            if scaled >= 0.995 { return String(format: "%.1f", scaled) + unit }
        }

        let megabytes = value / 1_000_000
        if megabytes >= 0.5 { return "\(Int(megabytes.rounded()))M" }
        return value > 0 ? "<1M" : "0"
    }
}

/// "1 items" is the kind of detail that makes a screen look unfinished, and this app asks
/// people to trust it with their photos.
///
/// Shared with the widget and the Live Activity for the same reason `ByteText` is.
public enum Counting {

    public static func items(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    public static func copies(_ count: Int) -> String {
        count == 1 ? "1 other copy" : "\(count) other copies"
    }
}
