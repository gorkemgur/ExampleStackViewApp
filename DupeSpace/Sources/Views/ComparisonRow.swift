import SwiftUI
import DupeCore

/// One measurement of two items, and whether they disagree on it.
struct ComparisonMetric: Identifiable {

    let label: String
    let keeperValue: String
    let candidateValue: String

    var id: String { label }
    var differs: Bool { keeperValue != candidateValue }
}

/// The measurements the app matched on, in the order a person checks them.
enum ComparisonMetrics {

    static func all(keeper: MediaItem, candidate: MediaItem) -> [ComparisonMetric] {
        [
            ComparisonMetric(label: "File", keeperValue: keeper.displayName, candidateValue: candidate.displayName),
            ComparisonMetric(
                label: "Resolution",
                keeperValue: "\(keeper.pixelWidth)×\(keeper.pixelHeight)",
                candidateValue: "\(candidate.pixelWidth)×\(candidate.pixelHeight)"
            ),
            ComparisonMetric(
                label: "Size",
                keeperValue: ByteFormatting.string(keeper.totalByteSize),
                candidateValue: ByteFormatting.string(candidate.totalByteSize)
            ),
            ComparisonMetric(
                label: "Taken",
                keeperValue: dateText(keeper.creationDate),
                candidateValue: dateText(candidate.creationDate)
            ),
            ComparisonMetric(
                label: "Kept because",
                keeperValue: keepReason(keeper),
                candidateValue: keepReason(candidate)
            ),
            // Last, and usually the same on both sides — which is exactly why it earns a row.
            // When it *differs* the highlights above pull it out on their own, and that is the
            // one comparison in this app that nothing else on the phone can make: Apple's own
            // Duplicates looks inside the photo library and stops there. The copy you exported
            // to Files and forgot about is invisible to it and, until this row existed, to
            // anyone reading this table too.
            ComparisonMetric(
                label: "Where",
                keeperValue: whereItLives(keeper),
                candidateValue: whereItLives(candidate)
            )
        ]
    }

    static func whereItLives(_ item: MediaItem) -> String {
        switch item.source {
        case .photoLibrary: return "Photo library"
        case .fileFolder: return "A folder you added"
        }
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

/// The one or two numbers that actually differ, pulled out of the table and set as chips.
///
/// The table below still carries everything; this is the answer to "what am I giving up", read
/// in a glance rather than by scanning five rows for the orange one.
struct ComparisonHighlights: View {

    let keeper: MediaItem
    let candidate: MediaItem

    var body: some View {
        let differing = ComparisonMetrics.all(keeper: keeper, candidate: candidate)
            .filter { $0.differs && $0.label != "File" }

        if differing.isEmpty {
            Text("Every measurement matches. This copy is interchangeable with the one being kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(differing) { metric in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(metric.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(metric.keeperValue)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .truncationMode(.middle)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)

                        Text(metric.candidateValue)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(DS.tier(.burstLeftover))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .truncationMode(.middle)

                        Spacer(minLength: 0)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Differences: " + differing
                    .map { "\($0.label), keeping \($0.keeperValue), this copy \($0.candidateValue)" }
                    .joined(separator: ". ")
            )
        }
    }
}

/// Says *why* two items were matched, and what the difference between them is.
///
/// This is the part a built-in duplicate finder does not give you: a value for the survivor,
/// a value for the copy, and a mark on the one that differs, so the decision is inspectable
/// rather than taken on trust.
struct ComparisonTable: View {

    let keeper: MediaItem
    let candidate: MediaItem

    /// Grows with the text size, so "Kept because" is not clipped by a box that never moves.
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 86

    var body: some View {
        let rows = ComparisonMetrics.all(keeper: keeper, candidate: candidate)

        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().overlay(DS.hairline)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(width: labelWidth, alignment: .leading)

                    // Filenames, dates and reason lists are all longer than the ~110pt each
                    // column gets on a phone; without this they wrap to four ragged lines.
                    Text(row.keeperValue)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(row.candidateValue)
                        .font(.caption.weight(row.differs ? .semibold : .regular))
                        .foregroundStyle(row.differs ? DS.tier(.burstLeftover) : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 7)
            }
        }
    }
}
