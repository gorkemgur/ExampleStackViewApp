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

                // What kind of thing this is, on the picture.
                //
                // A video's thumbnail is a frame, so it looks exactly like a photo — the only
                // thing distinguishing a 1.84 GB movie from a 410 KB still was the file
                // extension, which most people never see. The badge sits top-left, away from
                // the survivor's seal.
                if group.keeper.kind != .image {
                    Image(systemName: KindCopy.symbolName(for: group.keeper.kind))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .padding(3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

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

                // Only when there is a fraction to report. A group with one candidate beside a
                // tick box that is already either ticked or not says "1/1 ticked" — a second
                // reading of a control six points to its left, on a screen that prints a byte
                // figure four times before you reach a filename.
                if group.candidates.count > 1 {
                    Text("\(selectedCount)/\(group.candidates.count) ticked")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(selectedCount > 0 ? tint : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var detail: String {
        // Not "keeping this one · N other copies". That already truncated at the six-item
        // fixture size — "keeping this one · 1 othe…" — squeezed between a 52pt thumbnail and
        // a right column that grows to "999.9 MB" over "120/127 ticked" at real scale. The
        // seal on the picture says which one is being kept; the words only have to say how
        // many are on offer.
        Counting.copies(group.candidates.count)
    }
}
