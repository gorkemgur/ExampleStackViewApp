import SwiftUI
import DupeCore

struct BreakdownCardView: View {

    let breakdown: [CategoryBreakdown]
    let totalBytes: Int64

    private static let categoryColors: [CategoryBreakdown.Category: Color] = [
        .photos: .blue,
        .videos: .purple,
        .screenshots: .orange,
        .livePhotos: .teal,
        .documents: .brown
    ]

    var body: some View {
        Card("What it is made of", symbolName: "chart.pie", identifier: "breakdown.title") {
            CapacityBar(segments: segments, total: totalBytes, height: 14)

            VStack(spacing: 0) {
                ForEach(Array(breakdown.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
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
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 9)
    }
}
