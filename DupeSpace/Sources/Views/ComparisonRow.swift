import SwiftUI
import DupeCore

/// Says *why* two items were matched, and what the difference between them is.
///
/// This is the part a built-in duplicate finder does not give you: a value for the survivor,
/// a value for the copy, and a mark on the one that differs, so the decision is inspectable
/// rather than taken on trust.
struct ComparisonTable: View {

    let keeper: MediaItem
    let candidate: MediaItem

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.label) { row in
                if row.label != rows.first?.label {
                    Divider()
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 86, alignment: .leading)

                    Text(row.keeperValue)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(row.candidateValue)
                        .font(.caption.weight(row.differs ? .semibold : .regular))
                        .foregroundStyle(row.differs ? Color.orange : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 7)
            }
        }
    }

    private struct Row {
        let label: String
        let keeperValue: String
        let candidateValue: String
        var differs: Bool { keeperValue != candidateValue }
    }

    private var rows: [Row] {
        [
            Row(label: "File", keeperValue: keeper.displayName, candidateValue: candidate.displayName),
            Row(
                label: "Resolution",
                keeperValue: "\(keeper.pixelWidth)x\(keeper.pixelHeight)",
                candidateValue: "\(candidate.pixelWidth)x\(candidate.pixelHeight)"
            ),
            Row(
                label: "Size",
                keeperValue: ByteFormatting.string(keeper.totalByteSize),
                candidateValue: ByteFormatting.string(candidate.totalByteSize)
            ),
            Row(
                label: "Taken",
                keeperValue: Self.dateText(keeper.creationDate),
                candidateValue: Self.dateText(candidate.creationDate)
            ),
            Row(
                label: "Kept because",
                keeperValue: Self.keepReason(keeper),
                candidateValue: Self.keepReason(candidate)
            )
        ]
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        return dateFormatter.string(from: date)
    }

    private static func keepReason(_ item: MediaItem) -> String {
        var reasons: [String] = []
        if item.isFavorite { reasons.append("favourite") }
        if item.albumCount > 0 { reasons.append("in an album") }
        if item.isEdited { reasons.append("edited") }
        if item.isLivePhoto { reasons.append("Live Photo") }
        if item.isScreenshot { reasons.append("screenshot") }
        if !item.isLocallyAvailable { reasons.append("in iCloud") }
        return reasons.isEmpty ? "—" : reasons.joined(separator: ", ")
    }
}
