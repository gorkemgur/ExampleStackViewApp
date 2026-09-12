import SwiftUI
import DupeCore

/// The disk, as a gauge rather than as a card.
///
/// It sits straight on the page with no panel around it: it is the first thing on the screen
/// and the only reading the rest of the app is arguing about, so wrapping it in the same white
/// rectangle as "What this cannot see" would file it as one section among six.
struct StorageCardView: View {

    let snapshot: StorageSnapshot
    /// Bytes the photo library accounts for, when known.
    let libraryBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("Used on this iPhone", tint: DS.aqua)

                Readout.bytes(snapshot.usedCapacity, tint: DS.aqua)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(Motion.content, value: snapshot.usedCapacity)
                    .accessibilityIdentifier("storage.headline")

                Text("of \(ByteFormatting.string(snapshot.totalCapacity))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            CapacityBar(
                segments: parts.map { CapacityBar.Segment(id: $0.id, bytes: $0.bytes, color: $0.color) },
                total: snapshot.totalCapacity,
                height: 12
            )
            .accessibilityIdentifier("storage.bar")

            HStack(alignment: .top, spacing: 10) {
                ForEach(parts) { part in
                    legend(
                        color: part.color,
                        title: part.title,
                        bytes: part.bytes,
                        isActionable: part.isActionable
                    )
                }
            }

            Text("Free space is an estimate — iOS counts storage it can purge on demand as available.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("storage.caveat")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var otherBytes: Int64 {
        max(snapshot.usedCapacity - libraryBytes, 0)
    }

    private struct Part: Identifiable, Equatable {
        let id: String
        let title: String
        let bytes: Int64
        let color: Color
        var isActionable: Bool = false
    }

    /// The three parts of the disk, largest first.
    ///
    /// Sorted rather than fixed, because the bar is a comparison: reading it should tell you
    /// which of the three is biggest without doing arithmetic on the figures underneath. The
    /// legend is built from this same list, so the order under the bar can never disagree with
    /// the order in it.
    private var parts: [Part] {
        [
            Part(
                id: "library",
                title: "Photos & videos",
                bytes: min(libraryBytes, snapshot.usedCapacity),
                color: DS.deep,
                isActionable: true
            ),
            Part(id: "other", title: "Everything else", bytes: otherBytes, color: DS.neutral),
            Part(id: "free", title: "Free", bytes: snapshot.availableCapacity, color: DS.well)
        ]
        .sorted { $0.bytes > $1.bytes }
    }

    /// Each legend repeats its slug from the bar above rather than using a dot, so the eye can
    /// carry a colour straight from the measurement to the figure that names it.
    @ViewBuilder
    private func legend(
        color: Color,
        title: String,
        bytes: Int64,
        isActionable: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(height: 3)
                .frame(maxWidth: 34, alignment: .leading)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            // The library figure is the only one this app can do anything about, and on a
            // 343 GB disk it is a sliver of the bar. It gets the weight and the colour.
            Text(ByteFormatting.string(bytes))
                .font(.system(.footnote, design: .rounded).weight(isActionable ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(isActionable ? DS.deep : Color.primary)
                .lineLimit(1)
                // Three fixed columns, so at an accessibility text size the figure has to
                // shrink rather than push the one beside it off the screen.
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
