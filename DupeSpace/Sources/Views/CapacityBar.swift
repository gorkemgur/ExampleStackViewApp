import SwiftUI

/// A proportional bar. Segments are drawn in order and whatever is left over reads as free
/// space, so the bar always fills its track even when the segments do not add up to the total.
struct CapacityBar: View {

    struct Segment: Identifiable, Equatable {
        let id: String
        let bytes: Int64
        let color: Color

        init(id: String, bytes: Int64, color: Color) {
            self.id = id
            self.bytes = bytes
            self.color = color
        }
    }

    let segments: [Segment]
    let total: Int64
    var height: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: width(for: segment.bytes, in: proxy.size.width))
                }
                Rectangle()
                    .fill(Color(uiColor: .tertiarySystemFill))
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .animation(.smooth(duration: 0.45), value: segments)
        .animation(.smooth(duration: 0.45), value: total)
        .accessibilityHidden(true)
    }

    private func width(for bytes: Int64, in available: CGFloat) -> CGFloat {
        guard total > 0, bytes > 0 else { return 0 }
        let fraction = min(Double(bytes) / Double(total), 1)
        // Keep a hairline visible for a segment that is real but tiny, so "you have 40 MB of
        // duplicates" does not render as nothing at all.
        return max(available * fraction, 3)
    }
}
