import SwiftUI
import DupeCore

/// The deletion, while it happens and after it has.
///
/// This replaces a `ProgressView()` spinner that sat inside the red key — which is what a
/// network request looks like, on the one second in this product where a person is paying the
/// most attention and something irreversible is happening.
///
/// It is not a rocket and it is not a character sweeping up, and both were considered. A rocket
/// is takeoff, flight and arrival: a narrative that needs a measured duration, and this
/// operation has none — the photo half is one instant that happens behind a system alert
/// covering this screen. A figure "looking around" claims the app is inspecting and choosing
/// right now; it is not, the choosing happened on the previous screen and the user did it. Both
/// would be motion that means nothing in an app that has spent every other surface insisting
/// that a measurement must be real.
///
/// What it draws instead is the safety model as geometry — see `HandoverScene`. The only thing
/// that loops is the gate, and only while there is genuinely nothing to report.
struct HandoverView: View {

    let scene: HandoverScene
    /// The figure, once there is a true one. `nil` while the work is in flight.
    var settledBytes: Int64?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let laneHeight: CGFloat = 14
    private let laneGap: CGFloat = 6
    private let gateWidth: CGFloat = 1.5

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            GeometryReader { proxy in
                let gateX = proxy.size.width * stagingShare
                ZStack(alignment: .topLeading) {
                    lanes(in: proxy.size, gateX: gateX)
                    gate(height: proxy.size.height, x: gateX)
                }
            }
            .frame(height: totalHeight)

            captions
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deleting")
        .accessibilityValue(spokenValue)
        .accessibilityIdentifier("confirm.handover")
    }

    // MARK: - Geometry

    /// How much of the width is "this side of the gate". The rest is the hold.
    ///
    /// A files-only deletion has no hold at all, so the gate sits at the far end and there is
    /// nothing beyond it — the same component saying the opposite truth, which is the point of
    /// building it this way rather than as two screens.
    private var stagingShare: Double {
        scene.hasHold ? 0.62 : 0.94
    }

    private var totalHeight: CGFloat {
        let count = max(scene.lanes.count, 1)
        return CGFloat(count) * laneHeight + CGFloat(count - 1) * laneGap
    }

    private func lanes(in size: CGSize, gateX: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: laneGap) {
            ForEach(scene.lanes) { lane in
                laneRow(lane, width: size.width, gateX: gateX)
                    .frame(height: laneHeight)
            }
        }
    }

    @ViewBuilder
    private func laneRow(_ lane: HandoverScene.Lane, width: CGFloat, gateX: CGFloat) -> some View {
        let stagedWidth = max((gateX - DS.Space.s) * lane.widthShare, 2)
        let holdWidth = max((width - gateX - DS.Space.s) * (lane.holdShare > 0 ? 1 : 0), 0)

        ZStack(alignment: .leading) {
            // The recess beyond the gate, drawn whether or not anything is in it yet, so the
            // block visibly arrives somewhere rather than appearing out of nothing.
            if holdWidth > 0 {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(DS.neutralOnSlab.opacity(0.45), lineWidth: 1)
                    .frame(width: holdWidth)
                    .offset(x: gateX + DS.Space.s)
            }

            if lane.isAtomic {
                // One block. The photo half is atomic, so it has exactly one position at a
                // time: staged, or across.
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(lane.hasCrossed ? AnyShapeStyle(DS.neutralOnSlab) : AnyShapeStyle(DS.brandRow))
                    .frame(width: lane.hasCrossed ? max(holdWidth, 2) : stagedWidth)
                    .offset(x: lane.hasCrossed ? gateX + DS.Space.s : 0)
            } else {
                cells(lane, width: stagedWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : Motion.content, value: lane.hasCrossed)
    }

    /// The file lane: real cells, emptied from the far end inwards, one notch per settled file.
    ///
    /// `Canvas` rather than a stack of shapes: a hundred and seventy cells is a hundred and
    /// seventy view identities that SwiftUI would diff on every tick, and the cells themselves
    /// must not interpolate — a cell is consumed or it is not. The one thing that does
    /// interpolate is the mask over them, which is a single animatable width.
    private func cells(_ lane: HandoverScene.Lane, width: CGFloat) -> some View {
        let remaining = max(lane.cellCount - lane.settledCells, 0)
        let consumedShare = lane.cellCount > 0 ? Double(remaining) / Double(lane.cellCount) : 0

        return Canvas { context, size in
            guard lane.cellCount > 0 else { return }
            let gap = HandoverLayout.gap
            let cellWidth = max((size.width - gap * CGFloat(lane.cellCount - 1)) / CGFloat(lane.cellCount), 1)

            for index in 0..<lane.cellCount {
                let x = CGFloat(index) * (cellWidth + gap)
                let rect = CGRect(x: x, y: 0, width: cellWidth, height: size.height)
                // Refusals are reinstated from the outcome, never guessed at mid-flight: a
                // file that could not be removed is drawn in the muting neutral beside the
                // copy that explains it.
                let isRefused = index >= lane.cellCount - lane.refusedCells
                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(2, cellWidth / 2)),
                    with: isRefused ? .color(DS.neutral) : .style(DS.brandRow)
                )
            }
        }
        .frame(width: width)
        .mask(alignment: .leading) {
            // Trailing edge eats inwards. One animatable width, linear: this is a reading that
            // updates while work runs, which is exactly what `Motion.readout` exists for.
            Rectangle()
                .frame(width: width * consumedShare)
                .animation(reduceMotion ? nil : Motion.readout, value: consumedShare)
        }
    }

    /// The gate, and the one thing in this instrument allowed to loop.
    ///
    /// It loops only while `gateIsHeld` — that is, while the system's own confirmation is up and
    /// the atomic change has not returned. Stillness of the cargo plus motion of the gate says
    /// "nothing has happened yet; the system is deciding", which is the truth and is not
    /// something a spinner or a percentage can say.
    @ViewBuilder
    private func gate(height: CGFloat, x: CGFloat) -> some View {
        let line = Rectangle()
            .fill(Color.white.opacity(scene.gateIsHeld ? 0.35 : 0.75))
            .frame(width: gateWidth, height: height)

        if scene.gateIsHeld && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0)
                ZStack(alignment: .top) {
                    line
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: gateWidth, height: 10)
                        .blur(radius: 1.5)
                        // Ramped in and out at the ends so the wrap does not pop.
                        .opacity(travelOpacity(phase))
                        .offset(y: (height + 10) * phase - 10)
                }
                .frame(height: height, alignment: .top)
            }
            .offset(x: x)
        } else {
            line.offset(x: x)
        }
    }

    private func travelOpacity(_ phase: Double) -> Double {
        if phase < 0.15 { return phase / 0.15 }
        if phase > 0.85 { return (1 - phase) / 0.15 }
        return 1
    }

    // MARK: - Words

    @ViewBuilder
    private var captions: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(leadCaption)
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(DS.onSlabAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 6)

            Text(trailCaption)
                .font(.caption)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(DS.onSlabMuted)
                .lineLimit(1)
                .fixedSize()
        }
        .animation(reduceMotion ? nil : Motion.control, value: trailCaption)
    }

    private var leadCaption: String {
        switch scene.stage {
        case .photoLibrary: return "PHOTO LIBRARY"
        case .files: return "FILES"
        case .done: return scene.hasHold ? "GONE · HELD 30 DAYS" : "GONE"
        }
    }

    /// The sentence that makes the whole thing honest.
    ///
    /// "Settles in one step" is what a spinner cannot say and a percentage would contradict.
    private var trailCaption: String {
        if let settledBytes {
            return ByteText.string(settledBytes)
        }
        switch scene.stage {
        case .photoLibrary:
            return "Settles in one step"
        case .files:
            guard let files = scene.lanes.first(where: { $0.kind == .files }), files.cellCount > 0 else {
                return "Working"
            }
            return "\(files.settledCells * files.itemsPerCell) of \(files.cellCount * files.itemsPerCell)"
        case .done:
            return "Done"
        }
    }

    private var spokenValue: String {
        switch scene.stage {
        case .photoLibrary:
            return "Photo library, one change in progress"
        case .files:
            return "Files, \(trailCaption) removed"
        case .done:
            return scene.hasHold
                ? "Done. The photos are in Recently Deleted for thirty days."
                : "Done. The files are gone."
        }
    }
}
