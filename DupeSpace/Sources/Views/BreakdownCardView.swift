import SwiftUI
import DupeCore

struct BreakdownCardView: View {

    let breakdown: [CategoryBreakdown]
    let totalBytes: Int64

    /// Five hues walked round from the brand's blue rather than five system colours: this is
    /// a categorical scale, so what matters is that no two neighbours collide at a glance.
    private static let categoryColors: [CategoryBreakdown.Category: Color] = [
        .photos: DS.deep,
        .videos: Color(dsRGB: 0x7A5CF0),
        .screenshots: Color(dsRGB: 0xC77B12),
        .livePhotos: DS.aqua,
        .documents: Color(dsRGB: 0x8A7A6B)
    ]

    var body: some View {
        Card("What it is made of", symbolName: "chart.pie", identifier: "breakdown.title") {
            CapacityBar(segments: segments, total: totalBytes, height: 14)

            VStack(spacing: 0) {
                ForEach(Array(breakdown.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().overlay(DS.hairline)
                    }
                    row(entry)
                }
            }
        }
    }

    private var segments: [CapacityBar.Segment] {
        breakdown.map {
            CapacityBar.Segment(
                id: $0.id,
                bytes: $0.bytes,
                color: Self.categoryColors[$0.category] ?? .gray
            )
        }
    }

    @ViewBuilder
    private func row(_ entry: CategoryBreakdown) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.category.symbolName)
                .font(.footnote)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Self.categoryColors[entry.category] ?? .gray)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.category.title)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("breakdown.row.\(entry.id)")
                Text(Counting.items(entry.itemCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(ByteFormatting.string(entry.bytes))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
        }
        .padding(.vertical, 9)
    }
}
