import SwiftUI
import DupeCore

struct LargestItemsCardView: View {

    let items: [MediaItem]

    var body: some View {
        Card("Biggest single items", symbolName: "arrow.up.right.square", identifier: "largest.title") {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    row(item)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: MediaItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .video ? "film" : "photo")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(ByteFormatting.string(item.totalByteSize))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 9)
    }

    private func subtitle(for item: MediaItem) -> String {
        var parts: [String] = []
        if item.pixelWidth > 0 && item.pixelHeight > 0 {
            parts.append("\(item.pixelWidth)x\(item.pixelHeight)")
        }
        if item.duration > 0 {
            parts.append(durationText(item.duration))
        }
        if !item.isLocallyAvailable {
            parts.append("in iCloud")
        }
        return parts.joined(separator: " · ")
    }

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
