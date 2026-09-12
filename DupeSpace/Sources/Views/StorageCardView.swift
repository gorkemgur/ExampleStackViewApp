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

            CapacityBar(segments: segments, total: snapshot.totalCapacity, height: 12)
                .accessibilityIdentifier("storage.bar")

            HStack(alignment: .top, spacing: 10) {
                legend(color: DS.deep, title: "Photos & videos", bytes: libraryBytes, isActionable: true)
                legend(color: DS.neutral, title: "Everything else", bytes: otherBytes)
                legend(color: DS.well, title: "Free", bytes: snapshot.availableCapacity)
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

    private var segments: [CapacityBar.Segment] {
        [
            CapacityBar.Segment(id: "library", bytes: min(libraryBytes, snapshot.usedCapacity), color: DS.deep),
            CapacityBar.Segment(id: "other", bytes: otherBytes, color: DS.neutral)
        ]
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
