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
            ThumbnailView(item: group.keeper, side: 52, loader: loader)
                // What kind of thing this is, ON the picture.
                //
                // A video's thumbnail is a frame, so it looks exactly like a photo — the
                // only thing distinguishing a 1.84 GB movie from a 410 KB still was the
                // file extension, which most people never see.
                //
                // An overlay, not a second child of the `ZStack`. As a child it carried
                // `frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`,
                // and a `ZStack` takes the size of its largest child — so that child asked
                // for every point of width the row had, the stack grew far past the 52-point
                // thumbnail, and the badge was drawn out on the card's white background
                // about ninety points to the left of the picture it describes. Measured off
                // `04-review.png`: badge at x≈69pt, thumbnail spanning x≈99–134pt. The
                // comment said "on the picture" the whole time.
                .overlay(alignment: .topLeading) {
                    if group.keeper.kind != .image {
                        // A square frame, and that is the whole point of it.
                        //
                        // `Circle()` behind a padded glyph fills whatever frame the glyph
                        // asks for, and the video symbol is wide — so the "circle" came out
                        // as a stretched ellipse that reads as a rounded rectangle. Fixing
                        // the frame to 18 x 18 makes the circle a circle, and an 8-point
                        // glyph inside it leaves the disc visible around the symbol rather
                        // than being a ring drawn tight around it.
                        Image(systemName: KindCopy.symbolName(for: group.keeper.kind))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            // The ground is `DS.onPicture`, not `.black.opacity(0.55)`,
                            // and the ring is what makes it work on a dark frame. A fixed
                            // black disc has one failure mode at each end: it is a sticker
                            // on a white sky and it is invisible on a night shot. The disc
                            // keeps the glyph readable at the bright end, the hairline
                            // keeps the badge findable at the dark end, and `PaletteTests`
                            // holds both to 3:1 against the worst frame each can meet.
                            .background(Circle().fill(DS.onPicture))
                            .overlay(Circle().strokeBorder(DS.onPictureEdge, lineWidth: 0.5))
                            .padding(3)
                    }
                }
                // The survivor is marked on the picture rather than in the words: this is the copy
                // that stays, and the row is otherwise about what goes.
                //
                // It was `checkmark.seal.fill` in `.foregroundStyle(.white, DS.deep)` — a two-tone
                // glyph with no ground and no edge, drawn straight onto somebody's photograph. Two
                // things were wrong with that and only one of them needed a photograph to show up.
                // `DS.deep` is adaptive, and its dark value carries a white tick at 2.71:1, so the
                // tick dissolved into its own seal in dark mode on any frame at all. And with no
                // hairline the whole mark vanished on a frame near its own blue.
                //
                // Same construction as the kind badge above, which is the point: two marks on one
                // 52-point picture should be built the same way. The fill is
                // `DS.onPictureAccent` and not `DS.onPicture`, because blue is what says *survivor*
                // here and the neutral ground would throw that away.
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(DS.onPictureAccent))
                        .overlay(Circle().strokeBorder(DS.onPictureEdge, lineWidth: 0.5))
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
