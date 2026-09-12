import SwiftUI
import DupeCore

struct StorageCardView: View {

    let snapshot: StorageSnapshot
    /// Bytes the photo library accounts for, when known.
    let libraryBytes: Int64

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(ByteFormatting.string(snapshot.usedCapacity))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.4), value: snapshot.usedCapacity)
                    .accessibilityIdentifier("storage.headline")

                Text("used of \(ByteFormatting.string(snapshot.totalCapacity))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            CapacityBar(segments: segments, total: snapshot.totalCapacity, height: 18)
                .accessibilityIdentifier("storage.bar")

            HStack(spacing: 18) {
                legend(color: .accentColor, title: "Photos & videos", bytes: libraryBytes)
                legend(color: Color(uiColor: .systemGray3), title: "Everything else", bytes: otherBytes)
                legend(color: Color(uiColor: .tertiarySystemFill), title: "Free", bytes: snapshot.availableCapacity)
            }

            Text("Free space is an estimate — iOS counts storage it can purge on demand as available.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("storage.caveat")
        }
    }

    private var otherBytes: Int64 {
        max(snapshot.usedCapacity - libraryBytes, 0)
    }

    private var segments: [CapacityBar.Segment] {
        [
            CapacityBar.Segment(id: "library", bytes: min(libraryBytes, snapshot.usedCapacity), color: .accentColor),
            CapacityBar.Segment(id: "other", bytes: otherBytes, color: Color(uiColor: .systemGray3))
        ]
    }

    @ViewBuilder
    private func legend(color: Color, title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(ByteFormatting.string(bytes))
                .font(.footnote.weight(.medium))
        }
    }
}
