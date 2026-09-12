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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let side: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    face(candidate, image: candidateImage)

                    face(keeper, image: keeperImage)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: max(proxy.size.width * split, 0))
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
                chip("Keeping", tint: DS.tier(.inferiorCopy))
                Spacer(minLength: 0)
                chip("This copy", tint: DS.tier(.burstLeftover))
            }
            .accessibilityHidden(true)
        }
        .task(id: keeper.id) {
            keeperImage = await loader.thumbnail(for: keeper.id, size: CGSize(width: side, height: side))
        }
        .task(id: candidate.id) {
            candidateImage = await loader.thumbnail(for: candidate.id, size: CGSize(width: side, height: side))
        }
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

    private func chip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .kerning(0.8)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.14))
            )
    }

    private func placeholderSymbol(for item: MediaItem) -> String {
        if !item.isLocallyAvailable { return "icloud" }
        return item.kind == .video ? "film" : "photo"
    }
}
