import SwiftUI
import DupeCore

/// A ring of progress with someone sweeping the floor inside it, and a tick that comes out of
/// the middle when the work is done.
///
/// Drawn, not imported: no Lottie, no asset, no image file — a `Canvas` and about a dozen paths,
/// so it scales to any size, takes the app's own colours, and costs nothing to ship.
///
/// The one rule it keeps: the ring never claims a fraction nobody measured. A deletion's photo
/// half is a single atomic `PHPhotoLibrary.performChanges` behind the system's own confirmation
/// — ninety assets settle in one instant or none do — so while that is in flight the ring runs
/// a travelling arc and the figure sweeps on the spot. Once real settled counts arrive the arc
/// becomes a fill and the figure walks the floor, and the swept part of the floor *is* the
/// measurement. Everything to the left of the broom is done.
struct SweeperRingView: View {

    let scene: SweepScene
    var size: CGFloat = 132
    /// Drawn under the ring — the byte figure, or the count, or nothing.
    var caption: String?
    /// How long the deleter is actually taking between reports.
    ///
    /// The fill glides from the last report to the current one over this, so it arrives just as
    /// the next is due: always moving, and never ahead of what has happened. It used to be a
    /// fixed 0.15s, which on a cadence any slower than that advanced the ring and then left it
    /// sitting still — the step-by-step catching you can see when the demo is slowed down.
    ///
    /// And the curve is `.linear`, which is not a detail. An ease-out here starts each segment
    /// fast and brings it to a stop before the next report arrives, so a twelve-file deletion
    /// pulses twelve times instead of travelling. Constant velocity is what makes the joins
    /// between reports invisible; measured in the browser preview, the drawn arc advances at
    /// one speed through the whole phase to within floating point.
    var stepInterval: TimeInterval = 0.15

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of the tick has been drawn. Driven once, on arrival, so the mark strokes itself
    /// on rather than appearing.
    @State private var tickTrim: CGFloat = 0
    /// The single ring pulse that goes with it.
    @State private var pulse: CGFloat = 0
    /// The figure walking off, and the heap it collected going with it.
    ///
    /// Arrival is three beats rather than one: a tick that draws while someone is still
    /// standing under it reads as two things happening at once instead of one thing finishing.
    @State private var exit: CGFloat = 0

    private let lineWidth: CGFloat = 7

    var body: some View {
        VStack(spacing: DS.Space.s) {
            ZStack {
                track
                if scene.isFinished { ringPulse }
                progress
                interior
                if scene.isFinished { tick }
            }
            .frame(width: size, height: size)
            .animation(reduceMotion ? nil : Motion.content, value: scene.isFinished)
            .animation(reduceMotion ? nil : .linear(duration: stepInterval), value: scene.sweptFraction)
            .onAppear { if scene.isFinished { arrive() } }
            .onChange(of: scene.isFinished) { _, finished in
                if finished { arrive() } else { tickTrim = 0; pulse = 0; exit = 0 }
            }

            if let caption {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(DS.onSlabMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scene.isFinished ? "Done" : "Deleting")
        .accessibilityValue(spokenValue)
        .accessibilityIdentifier("sweeper")
    }

    // MARK: - The ring

    private var track: some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.10), lineWidth: lineWidth)
    }

    /// Filled when there is something to fill it with; a travelling arc when there is not.
    @ViewBuilder
    private var progress: some View {
        if scene.isWorking && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: false)) { timeline in
                let turn = phase(timeline.date, period: 1.4)
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: 0.24)
                    .stroke(DS.brandRow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90 + turn * 360))
            }
        } else {
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: max(scene.ringFraction, scene.isWorking ? 0.24 : 0))
                .stroke(DS.brandRow, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: stepInterval), value: scene.ringFraction)
        }
    }

    // MARK: - Inside it

    /// The floor, the specks still on it, and the person sweeping them up.
    @ViewBuilder
    private var interior: some View {
        if reduceMotion {
            // A held pose, mid-stroke, at the true position. Nothing moves and nothing is lost:
            // the swept floor still says exactly how far the work has got.
            figure(phase: 0.25)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: scene.isFinished && exit >= 1)) { timeline in
                figure(phase: phase(timeline.date, period: 0.9))
            }
        }
    }

    private func figure(phase: Double) -> some View {
        let x = SweeperFigure.standingX(for: scene, workingPhase: phase)
        let pose = SweeperFigure.pose(x: x, phase: phase, sweeping: true)

        return Canvas { context, canvas in
            // Same duration as the ring, for the same reason: the figure should walk between
            // reports rather than jump a twelfth of the floor at each one.
            func point(_ unit: CGPoint) -> CGPoint {
                CGPoint(x: unit.x * canvas.width, y: unit.y * canvas.height)
            }

            let floorY = SweeperFigure.floorY * canvas.height
            let inset = canvas.width * 0.2

            // THE FLOOR
            //
            // It was a hairline with dots on it, which reads as a diagram rather than as a
            // place. The rule fades out at both ends instead of stopping dead, the figure
            // casts a shadow so it stands on something, and the swept part carries a trail
            // that is brightest right behind the broom.
            var floor = Path()
            floor.move(to: CGPoint(x: inset, y: floorY))
            floor.addLine(to: CGPoint(x: canvas.width - inset, y: floorY))
            context.stroke(
                floor,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: DS.onSlabMuted.opacity(0), location: 0),
                        .init(color: DS.onSlabMuted.opacity(0.3), location: 0.18),
                        .init(color: DS.onSlabMuted.opacity(0.3), location: 0.82),
                        .init(color: DS.onSlabMuted.opacity(0), location: 1)
                    ]),
                    startPoint: CGPoint(x: inset, y: floorY),
                    endPoint: CGPoint(x: canvas.width - inset, y: floorY)
                ),
                lineWidth: 1
            )

            let sweptTo = scene.isFinished
                ? canvas.width - inset
                : min(pose.broomLeft.x * canvas.width, canvas.width - inset)

            if sweptTo > inset {
                var swept = Path()
                swept.move(to: CGPoint(x: inset, y: floorY))
                swept.addLine(to: CGPoint(x: sweptTo, y: floorY))
                context.opacity = scene.isFinished ? Double(1 - exit) : 1
                context.stroke(
                    swept,
                    with: .linearGradient(
                        Gradient(colors: [DS.onSlabAccent.opacity(0), DS.onSlabAccent.opacity(0.85)]),
                        startPoint: CGPoint(x: inset, y: floorY),
                        endPoint: CGPoint(x: sweptTo, y: floorY)
                    ),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                )
                context.opacity = 1
            }

            if !scene.isFinished {
                // The shadow. It narrows as the body leans into a stroke, which is the cheapest
                // way to make a walk read as weight rather than as a sprite sliding along.
                let squash = 1 - abs(sin(phase * 2 * .pi)) * 0.18
                let shadowWidth = canvas.width * 0.115 * squash
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: x * canvas.width - shadowWidth / 2,
                            y: floorY - 1,
                            width: shadowWidth,
                            height: canvas.height * 0.022
                        )
                    ),
                    with: .color(DS.ink.opacity(0.55))
                )
            }

            // What is left to do, at its own size rather than fourteen identical dots. Nothing
            // once the work is finished: the figure travels to `travel.upperBound`, which is
            // short of the far edge, so two specks used to sit there uncollected under a tick
            // claiming the job was done.
            let grain = SweepFloor.grain()
            for (index, speck) in SweepFloor.specks().enumerated()
            where !scene.isFinished && !SweepFloor.isSwept(speck, by: x) {
                let dot = point(speck)
                let r = grain[index]
                context.fill(
                    Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)),
                    with: .color(DS.onSlabMuted.opacity(0.55))
                )
            }

            // THE HEAP
            //
            // What the broom has actually collected, riding in front of it and growing with the
            // count. The same reading as the swept floor, in the form of a thing rather than a
            // measurement — and the part that makes the figure look like it is doing work
            // rather than walking.
            let collected = SweepFloor.collected(by: x)
            if collected > 0 && !scene.isFinished {
                let heap = point(CGPoint(x: pose.broomRight.x + 0.012, y: SweeperFigure.floorY))
                let w = canvas.width * (0.03 + Double(collected) * 0.0085)
                let h = canvas.height * (0.018 + Double(collected) * 0.0047)
                var pile = Path()
                pile.move(to: CGPoint(x: heap.x - w, y: heap.y))
                pile.addQuadCurve(
                    to: CGPoint(x: heap.x, y: heap.y - h * 0.72),
                    control: CGPoint(x: heap.x - w * 0.35, y: heap.y - h)
                )
                pile.addQuadCurve(
                    to: CGPoint(x: heap.x + w, y: heap.y),
                    control: CGPoint(x: heap.x + w * 0.5, y: heap.y - h * 0.3)
                )
                pile.closeSubpath()
                context.fill(pile, with: .color(DS.onSlabMuted.opacity(0.65)))
            }

            // And the puff as the figure steps off, so the heap is disposed of rather than
            // simply deleted from the picture.
            if scene.isFinished && exit < 1 {
                let origin = point(CGPoint(x: SweeperFigure.travel.upperBound + 0.13, y: SweeperFigure.floorY))
                for index in 0..<5 {
                    let angle = -Double.pi * (0.15 + Double(index) * 0.175)
                    let distance = exit * canvas.width * 0.12
                    let r = 2.6 * (1 - exit)
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: origin.x + cos(angle) * distance - r,
                                y: origin.y + sin(angle) * distance * 0.8 - r,
                                width: r * 2,
                                height: r * 2
                            )
                        ),
                        with: .color(DS.onSlabMuted.opacity(0.5 * (1 - exit)))
                    )
                }
            }

            // The figure keeps walking through the exit beat, then it is gone.
            guard !scene.isFinished || exit < 1 else { return }
            context.translateBy(x: exit * canvas.width * 0.16, y: 0)
            context.opacity = Double(1 - exit)

            let body = GraphicsContext.Shading.color(DS.onSlab)

            // Legs.
            var legs = Path()
            legs.move(to: point(pose.frontFoot))
            legs.addLine(to: point(pose.hip))
            legs.addLine(to: point(pose.backFoot))
            context.stroke(legs, with: body, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            // Spine.
            var spine = Path()
            spine.move(to: point(pose.hip))
            spine.addLine(to: point(pose.shoulder))
            context.stroke(spine, with: body, style: StrokeStyle(lineWidth: 4, lineCap: .round))

            // Head.
            let head = point(pose.head)
            let headSize = canvas.width * 0.075
            context.fill(
                Path(ellipseIn: CGRect(x: head.x - headSize / 2, y: head.y - headSize / 2, width: headSize, height: headSize)),
                with: body
            )

            // Arm to the grip, then the broom handle down to the floor.
            var arm = Path()
            arm.move(to: point(pose.shoulder))
            arm.addLine(to: point(pose.grip))
            context.stroke(arm, with: body, style: StrokeStyle(lineWidth: 3, lineCap: .round))

            let broomCentre = CGPoint(
                x: (pose.broomLeft.x + pose.broomRight.x) / 2,
                y: SweeperFigure.floorY - 0.03
            )
            var handle = Path()
            handle.move(to: point(pose.grip))
            handle.addLine(to: point(broomCentre))
            context.stroke(
                handle,
                with: .color(DS.onSlabAccent),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )

            // The brush: a wedge, not a rectangle — a rectangle on a stick reads as a hammer.
            var brush = Path()
            brush.move(to: point(CGPoint(x: broomCentre.x - 0.02, y: broomCentre.y)))
            brush.addLine(to: point(CGPoint(x: broomCentre.x + 0.02, y: broomCentre.y)))
            brush.addLine(to: point(pose.broomRight))
            brush.addLine(to: point(pose.broomLeft))
            brush.closeSubpath()
            context.fill(brush, with: .color(DS.onSlabAccent))

            // Two specks lifting off the brush, so the stroke visibly does something.
            let lift = abs(sin(phase * 2 * .pi))
            for offset in [0.035, 0.06] {
                let dust = point(
                    CGPoint(
                        x: pose.broomRight.x + offset,
                        y: SweeperFigure.floorY - 0.02 - lift * offset
                    )
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: dust.x - 1.4, y: dust.y - 1.4, width: 2.8, height: 2.8)),
                    with: .color(DS.onSlabAccent.opacity(0.55 * (1 - lift * 0.5)))
                )
            }
        }
    }

    // MARK: - Arrival

    /// The tick, out of the middle of the ring.
    ///
    /// It strokes itself on rather than appearing, and the ring pulses once behind it. That is
    /// the whole celebration: no confetti, no trophy, no second haptic. This is a destruction
    /// the person authorised, not a level cleared.
    private var tick: some View {
        TickMark()
            .trim(from: 0, to: tickTrim)
            .stroke(DS.onSlabAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            .frame(width: size * 0.42, height: size * 0.42)
            // The only flourish in the whole thing, and it is three and a half per cent.
            .scaleEffect(tickTrim >= 1 ? 1 + sin(min(pulse, 1) * .pi) * 0.035 : 1)
            .accessibilityIdentifier("sweeper.tick")
    }

    /// One pulse off the ring, and only one.
    private var ringPulse: some View {
        Circle()
            .strokeBorder(DS.onSlabAccent.opacity(0.5 * (1 - pulse)), lineWidth: 3)
            .scaleEffect(1 + pulse * 0.12)
    }

    /// Arrival, driven once rather than per frame.
    ///
    /// The web preview of this had the bug in its clearest form: it rebuilt the tick on every
    /// frame at dash-offset zero, so the mark restarted sixty times a second and never drew a
    /// pixel of itself — the finished state appeared to show nothing at all.
    private func arrive() {
        guard !reduceMotion else {
            tickTrim = 1
            pulse = 1
            exit = 1
            return
        }
        tickTrim = 0
        pulse = 0
        exit = 0
        withAnimation(.easeOut(duration: 0.26)) { exit = 1 }
        withAnimation(.snappy(duration: 0.42).delay(0.26)) { tickTrim = 1 }
        withAnimation(.easeOut(duration: 0.56).delay(0.26)) { pulse = 1 }
    }

    private var spokenValue: String {
        switch scene.mode {
        case .working: return "Working. This step cannot be counted through."
        case let .counting(fraction): return "\(Int(fraction * 100)) per cent"
        case .finished: return caption ?? "Finished"
        }
    }

    /// A 0...1 cycle from the wall clock, so every instance of this view is on the same beat
    /// rather than each starting its own when it happens to appear.
    private func phase(_ date: Date, period: Double) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }
}

/// The check itself. A `Shape`, so it can be trimmed, scaled and animated like any other.
struct TickMark: Shape {

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.20))
        return path
    }
}
