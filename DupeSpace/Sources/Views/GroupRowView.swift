import SwiftUI
import DupeCore

/// One duplicate group as it appears on the ladder: the survivor, then the copies on offer,
/// with the count that is currently ticked.
struct GroupRowView: View {

    let group: ReviewGroup
    let selectedCount: Int
    /// The rung's colour, so a row never has to explain which tier it belongs to.
    var tint: Color = DS.deep
    let loader: any ThumbnailLoading

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ThumbnailView(item: group.keeper, side: 52, loader: loader)

                // The survivor is marked on the picture rather than in the words: this is the
                // copy that stays, and the row is otherwise about what goes.
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.white, DS.deep)
                    .padding(3)
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
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()

                Text("\(selectedCount)/\(group.candidates.count) ticked")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(selectedCount > 0 ? tint : Color.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var detail: String {
        return "keeping this one · \(Counting.copies(group.candidates.count))"
    }
}
