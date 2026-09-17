import SwiftUI
import DupeCore

/// The disk, as a gauge rather than as a card.
///
/// It sits straight on the page with no panel around it: it is the first thing on the screen
/// and the only reading the rest of the app is arguing about, so wrapping it in the same white
/// rectangle as "What this cannot see" would file it as one section among six.
struct StorageCardView: View {

    let snapshot: StorageSnapshot
    /// Bytes the photo library accounts for, when known.
    let libraryBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The hero is the figure this app can do something about.
            //
            // It used to be the whole disk: 298.86 GB at 34pt heavy, a number no button in
            // this app can move, with the 4.55 GB of photos and videos — the only quantity the
            // product exists to act on — set at 13pt in the third column of a legend
            // underneath. A 2.6x inversion of the hierarchy, in the opening frame.
            //
            // The disk is still here, in the line under the hero and drawn across the bar. It
            // is the context; it was never the subject.
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                // The slug is the key for the bar below: the library is a sliver of a
                // 343 GB disk, and dropping its legend column when it became the headline
                // left that sliver as an unexplained colour.
                Eyebrow(heroTitle, tint: DS.deep, slug: knowsLibrary)

                Readout.bytes(heroBytes, tint: DS.deep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(Motion.content, value: heroBytes)
                    .accessibilityIdentifier("storage.headline")

                Text(context)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CapacityBar(
                segments: usedParts.map { CapacityBar.Segment(id: $0.id, bytes: $0.bytes, color: $0.color) },
                total: snapshot.totalCapacity,
                height: 12
            )
            .accessibilityIdentifier("storage.bar")

            // Not an `HStack` of independent columns: each used to be its own `VStack`, so a
            // title that wrapped to two lines ("Everything else", at AX5) grew only its own
            // column, while a short one ("Free") stayed on one line. The two never shared a
            // row, so the byte figure that followed sat at whatever height its own title left
            // off — lower under the wrapped title than under the one that did not wrap. `Grid`
            // lays out by row instead of by column: every column's swatch, title and figure
            // share the same three rows, so the figures line up regardless of how many lines
            // the title above any one of them took.
            Grid(alignment: .leading, horizontalSpacing: DS.Space.m, verticalSpacing: 5) {
                GridRow {
                    ForEach(legendParts) { part in legendSwatch(color: part.color) }
                }
                GridRow {
                    ForEach(legendParts) { part in legendTitle(part.title, id: part.id) }
                }
                GridRow {
                    ForEach(legendParts) { part in
                        legendBytes(part.bytes, isActionable: part.isActionable, id: part.id)
                    }
                }
            }

            Text("Free space is an estimate — iOS counts storage it can purge on demand as available.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("storage.caveat")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var otherBytes: Int64 {
        max(snapshot.usedCapacity - libraryBytes, 0)
    }

    /// Before the inventory has been read there is no library figure to lead with, so the card
    /// leads with the disk and says so. Promoting a zero would be worse than either.
    private var knowsLibrary: Bool { libraryBytes > 0 }

    private var heroTitle: String {
        knowsLibrary ? "Photos & videos on this iPhone" : "Used on this iPhone"
    }

    private var heroBytes: Int64 {
        knowsLibrary ? min(libraryBytes, snapshot.usedCapacity) : snapshot.usedCapacity
    }

    private var context: String {
        knowsLibrary
            ? "of \(ByteFormatting.string(snapshot.usedCapacity)) used, on a \(ByteFormatting.string(snapshot.totalCapacity)) iPhone"
            : "of \(ByteFormatting.string(snapshot.totalCapacity))"
    }

    private struct Part: Identifiable, Equatable {
        let id: String
        let title: String
        let bytes: Int64
        let color: Color
        var isActionable: Bool = false
    }

    /// What is on the disk, largest first.
    ///
    /// Sorted rather than fixed, because the bar is a comparison: reading it should tell you
    /// which part is biggest without doing arithmetic on the figures underneath.
    ///
    /// Free space is deliberately not in here. It is the track's own remainder, so the bar
    /// fills left to right with what is used and stops where the disk runs out — which is how
    /// a disk reads. Sorting it in with the rest put Free between the two used segments on any
    /// phone with room to spare, breaking the bar into two unrelated pieces, and painted it in
    /// the same colour the track already uses for its empty end, so it was invisible anyway.
    private var usedParts: [Part] {
        [
            Part(
                id: "library",
                title: "Photos & videos",
                bytes: min(libraryBytes, snapshot.usedCapacity),
                color: DS.deep,
                isActionable: true
            ),
            Part(id: "other", title: "Everything else", bytes: otherBytes, color: DS.neutral)
        ]
        .sorted { $0.bytes > $1.bytes }
    }

    /// The legend, in the order the bar draws them: the used parts largest first, then the
    /// empty end of the track. The order under the bar can never disagree with the order in it.
    ///
    /// The library's own column is dropped once it is the hero — the slug above the headline is
    /// already its key, and repeating a figure at two sizes on one card makes the reader check
    /// whether they are the same number.
    private var legendParts: [Part] {
        let tail = Part(id: "free", title: "Free", bytes: snapshot.availableCapacity, color: DS.well)
        guard knowsLibrary else { return usedParts + [tail] }
        return usedParts.filter { $0.id != "library" } + [tail]
    }

    /// Each legend repeats its slug from the bar above rather than using a dot, so the eye can
    /// carry a colour straight from the measurement to the figure that names it.
    ///
    /// One `Grid` row per part, so this is one cell rather than a whole column: outlined as
    /// well as filled, because "Free" carries the colour of the track's empty end, which is a
    /// shade off the page it is drawn on, so without an edge that swatch was a blank space
    /// above the word.
    @ViewBuilder
    private func legendSwatch(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 0.5)
            )
            .frame(height: 3)
            .frame(maxWidth: 34, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func legendTitle(_ title: String, id: String) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("storage.legend.\(id).title")
    }

    /// The library figure is the only one this app can do anything about, and on a 343 GB disk
    /// it is a sliver of the bar. It gets the weight and the colour.
    @ViewBuilder
    private func legendBytes(_ bytes: Int64, isActionable: Bool, id: String) -> some View {
        Text(ByteFormatting.string(bytes))
            .font(.system(.footnote, design: .rounded).weight(isActionable ? .bold : .medium))
            .monospacedDigit()
            .foregroundStyle(isActionable ? DS.deep : Color.primary)
            .lineLimit(1)
            // Every column is flexible-width, so at an accessibility text size the figure has
            // to shrink rather than push the one beside it off the screen.
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("storage.legend.\(id).bytes")
    }
}
