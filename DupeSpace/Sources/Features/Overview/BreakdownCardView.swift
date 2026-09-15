import SwiftUI
import DupeCore

struct BreakdownCardView: View {

    let breakdown: [CategoryBreakdown]
    let totalBytes: Int64

    /// One hue, five steps.
    ///
    /// This used to claim to be "five hues walked round from the brand's blue". A violet at
    /// 258 degrees and a twelve-per-cent-saturation taupe are not walked round from 210, and
    /// the ochre landed within eight degrees of `tier(.burstLeftover)` — so a chip for
    /// screenshots and a rail meaning "a burst you probably do not want" were the same colour
    /// saying different things. That violet bar was the loudest arbitrary colour in the app.
    ///
    /// The bar is sorted, so this is an ordered quantity rather than five unrelated
    /// categories, and an ordered quantity is a ramp. The card now reads as one library split
    /// five ways instead of as five apps' icons in a row.
    private static func color(for category: CategoryBreakdown.Category) -> Color {
        switch category {
        case .photos: return DS.adaptive(light: 0x0A6FE0, dark: 0x3DA1FF)
        case .videos: return DS.adaptive(light: 0x3D91E8, dark: 0x6FB8FF)
        case .screenshots: return DS.adaptive(light: 0x6FAEEF, dark: 0x96CBFF)
        case .livePhotos: return DS.adaptive(light: 0xA0CAF5, dark: 0xBCDDFF)
        case .documents: return DS.adaptive(light: 0xCFE3FA, dark: 0xDCEEFF)
        }
    }

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
                color: Self.color(for: $0.category)
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
                        .fill(Self.color(for: entry.category))
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
