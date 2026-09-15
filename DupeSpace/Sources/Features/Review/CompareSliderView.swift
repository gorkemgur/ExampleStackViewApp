import SwiftUI
import DupeCore

/// The two copies on top of each other, with a divider you drag.
///
/// Every duplicate cleaner shows you two thumbnails side by side and leaves you to flick your
/// eyes between them, which is exactly the comparison a human is worst at. Stacked and wiped,
/// the difference sits in one place on the retina: a softer edge, a crop, a different frame of
/// the same burst. The table underneath still carries every measurement, and VoiceOver drives
/// the same wipe with the adjustable action rather than being handed a picture it cannot see.
struct CompareSliderView: View {

    let keeper: MediaItem
    let candidate: MediaItem
    let loader: any ThumbnailLoading

    @State private var split: CGFloat = 0.55
    @State private var keeperImage: UIImage?
    @State private var candidateImage: UIImage?

    /// Where the two differ, computed from the same grayscale buffers the fingerprints came
    /// from. `nil` until both faces have loaded; a grid with nothing in it means they agree.
    @State private var difference: DifferenceGrid?
    @State private var showingDifference = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The comparator is 180pt tall and never wider than the screen.
    ///
    /// It was asking for 400 points, which the loader multiplies by the display scale into a
    /// 1200x1200 pixel request — about six megabytes decoded, per face. A group of sixty
    /// copies is a hundred and twenty of those, and sixty of them are the same survivor asked
    /// for sixty times. Asking for what is drawn is the whole fix; the loader's cache takes
    /// care of the survivor being asked for at all.
    private let side: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    face(candidate, image: candidateImage)

                    face(keeper, image: keeperImage)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: max(proxy.size.width * split, 0))
                        }

                    if showingDifference, let difference, !difference.isBelowNoiseFloor {
                        DifferenceOverlay(grid: difference)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }

                    divider(at: proxy.size.width * split, height: proxy.size.height)
                }
                .contentShape(Rectangle())
                // Eight points, not zero: at zero the wipe claims the touch the instant a finger
                // lands on it, and the screen underneath stops scrolling.
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            let fraction = value.location.x / max(proxy.size.width, 1)
                            split = min(max(fraction, 0), 1)
                        }
                )
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
            .animation(reduceMotion ? nil : Motion.control, value: split)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Compare the copy being kept with this one")
            .accessibilityValue("\(Int((split * 100).rounded())) percent of the kept copy is showing")
            .accessibilityHint("Swipe up or down to wipe between the two copies")
            .accessibilityAdjustableAction { direction in
                if direction == .increment {
                    split = min(split + 0.2, 1)
                } else {
                    split = max(split - 0.2, 0)
                }
            }

            HStack(spacing: 8) {
                chip("Keeping", tint: DS.deep)
                Spacer(minLength: 0)
                differenceToggle
                chip("This copy", tint: DS.neutral)
            }
        }
        .animation(reduceMotion ? nil : Motion.control, value: showingDifference)
        .task(id: keeper.id) {
            keeperImage = await loader.thumbnail(for: keeper.id, size: CGSize(width: side, height: side))
            await computeDifference()
        }
        .task(id: candidate.id) {
            candidateImage = await loader.thumbnail(for: candidate.id, size: CGSize(width: side, height: side))
            await computeDifference()
        }
    }

    /// The promise `docs/CONCEPT.md` makes second, after "the gain comes first": the match is
    /// shown, not asserted. The wipe already lets someone see *that* two copies are alike; this
    /// says *where* they are not.
    ///
    /// Off by default. It is evidence to be asked for, and a heat map permanently over the
    /// photograph would make every comparison look like a diagnostic readout instead of two
    /// pictures.
    @ViewBuilder
    private var differenceToggle: some View {
        if let difference {
            Button {
                showingDifference.toggle()
            } label: {
                Label(
                    difference.isBelowNoiseFloor ? "No visible difference" : "Where they differ",
                    systemImage: difference.isBelowNoiseFloor ? "equal.circle" : "square.grid.3x3.topleft.filled"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(showingDifference ? DS.deep : Color.secondary)
                .padding(.horizontal, 9)
                .frame(minHeight: 32)
                .background(
                    Capsule(style: .continuous)
                        .fill(showingDifference ? DS.deep.opacity(0.13) : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(showingDifference ? DS.deep.opacity(0.4) : DS.hairline, lineWidth: 1)
                )
                // Pill 32pt, hit area 44pt — the pattern `ReviewView.orderPicker` carries.
                // A `.contentShape(Capsule())` used to stand here, which reads like the fix
                // and is its opposite: a content shape *confines* the touch to the shape it is
                // handed, and cannot make a target taller than the frame underneath it.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(difference.isBelowNoiseFloor)
            .accessibilityIdentifier("candidate.difference.\(candidate.id)")
        }
    }

    /// Off the main actor: this is two 64×64 renders and about eight thousand subtractions, on
    /// a screen that can hold sixty of these.
    private func computeDifference() async {
        guard let keeperImage, let candidateImage, difference == nil else { return }

        let a = keeperImage.cgImage
        let b = candidateImage.cgImage
        guard let a, let b else { return }

        difference = await Task.detached(priority: .utility) {
            guard
                let left = GrayImageRenderer.render(a),
                let right = GrayImageRenderer.render(b)
            else {
                return nil
            }
            return DifferenceGrid.between(left, right)
        }.value
    }

    @ViewBuilder
    private func face(_ item: MediaItem, image: UIImage?) -> some View {
        ZStack {
            DS.well

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // An item with no local preview is usually one deliberately left in iCloud, and
                // the view should say so rather than show an empty box.
                Image(systemName: placeholderSymbol(for: item))
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func divider(at x: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 2)
                .shadow(color: .black.opacity(0.35), radius: 2)

            Circle()
                .fill(.white)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "arrow.left.and.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(dsRGB: 0x0C1B2B))
                )
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        }
        .frame(width: 44, height: height)
        .position(x: x, y: height / 2)
        .allowsHitTesting(false)
    }

    /// The two labels under the comparison, on the screen where somebody decides which
    /// photograph dies.
    ///
    /// They were the tint at 14 % behind the tint as text, uppercase and kerned — the exact
    /// pattern `DesignSystem.swift` records replacing on `Badge`, and for the exact reason:
    /// `DS.neutral` on its own 14 % ground measures 1.92:1 in light and **1.77:1** in dark. The
    /// layout half of that cleanup landed here and the drawing half did not, so the retired
    /// pattern was still being drawn under every comparison.
    ///
    /// `Badge` now chooses its ink from its fill, which is what makes it usable with a neutral
    /// at all. The ink it picks is not the same one in both appearances and not because the
    /// appearance changed: `DS.neutral` is light in light mode, so the ink goes dark and
    /// measures 9.03:1; it is a dark slate in dark mode, so the ink goes white and measures
    /// 7.50:1.
    private func chip(_ title: String, tint: Color) -> some View {
        Badge(title, tint: tint)
    }

    private func placeholderSymbol(for item: MediaItem) -> String {
        if !item.isLocallyAvailable { return "icloud" }
        return item.kind == .video ? "film" : "photo"
    }
}

/// The heat map itself: one translucent square per grid cell, over the two faces.
///
/// Drawn in the app's own warning amber rather than the usual red-to-blue thermal ramp. Red on
/// this screen means the irreversible key, and a picture that borrows it would read as "these
/// pixels are the problem" rather than "these pixels are where the two differ".
struct DifferenceOverlay: View {

    let grid: DifferenceGrid

    var body: some View {
        Canvas { context, size in
            guard grid.size > 0 else { return }

            let cellWidth = size.width / CGFloat(grid.size)
            let cellHeight = size.height / CGFloat(grid.size)
            let tint = DS.tier(.burstLeftover)

            for y in 0..<grid.size {
                for x in 0..<grid.size {
                    let value = grid.cell(x: x, y: y)
                    // Nothing under a tenth is painted at all. A faint wash over the whole
                    // picture would say "everything differs a little", which is both true of
                    // any re-encode and useless to look at.
                    guard value > 0.1 else { continue }

                    let rect = CGRect(
                        x: CGFloat(x) * cellWidth,
                        y: CGFloat(y) * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                    context.fill(
                        Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2),
                        with: .color(tint.opacity(0.15 + value * 0.45))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
