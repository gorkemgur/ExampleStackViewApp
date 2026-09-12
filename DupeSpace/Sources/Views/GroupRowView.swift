import SwiftUI
import DupeCore

/// One duplicate group as it appears in the review list: the survivor, then the copies on
/// offer, with the count that is currently ticked.
struct GroupRowView: View {

    let group: ReviewGroup
    let selectedCount: Int
    let loader: any ThumbnailLoading

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ThumbnailView(item: group.keeper, side: 56, loader: loader)
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.white, .green)
                    .padding(4)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(group.keeper.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteFormatting.string(group.bytes))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()

                Text("\(selectedCount)/\(group.candidates.count) ticked")
                    .font(.caption2)
                    .foregroundStyle(selectedCount > 0 ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        return "keeping this one · \(Counting.copies(group.candidates.count))"
    }
}
