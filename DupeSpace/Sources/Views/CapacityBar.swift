import SwiftUI

/// A proportional bar. Segments are drawn in order and whatever is left over reads as free
/// space, so the bar always fills its track even when the segments do not add up to the total.
///
/// Drawn as separated rounded slugs rather than one continuous capsule: on a 343 GB disk the
/// part this app can act on is a sliver, and a sliver inside a single capsule reads as a
/// rendering seam rather than as a measurement.
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
        MeterTrack(
            segments: segments.map {
                MeterTrack.Segment(id: $0.id, value: Double($0.bytes), color: $0.color)
            },
            total: Double(max(total, 0)),
            height: height
        )
        .accessibilityHidden(true)
    }
}
