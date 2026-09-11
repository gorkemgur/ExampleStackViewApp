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
                    .padding(2)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(group.keeper.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteFormatting.string(group.bytes))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()

                Text("\(selectedCount)/\(group.candidates.count) ticked")
                    .font(.caption2)
                    .foregroundStyle(selectedCount > 0 ? Color.accentColor : Color.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        let copies = group.candidates.count == 1 ? "1 other copy" : "\(group.candidates.count) other copies"
        return "keeping this one · \(copies)"
    }
}
