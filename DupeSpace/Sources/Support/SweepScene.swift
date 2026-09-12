import CoreGraphics
import Foundation
import DupeCore

/// Where the sweeper is, how far the ring has come round, and what is still on the floor.
///
/// Pure — no SwiftUI in here — because the drawing is the easy half. The half that must not go
/// wrong is that the ring never claims a fraction the deleter did not give it. The photo half
/// of a deletion is one atomic `PHPhotoLibrary.performChanges` behind the system's own
/// confirmation: ninety assets settle in one instant or none do, so there is no percentage to
/// draw. In that state the ring runs as a travelling arc and the figure sweeps on the spot —
/// motion that says "working", not a number that says "sixty per cent".
struct SweepScene: Equatable {

    enum Mode: Equatable {
        /// Something is happening and nothing can be counted yet.
        case working
        /// Real settled work, as a fraction of the whole.
        case counting(Double)
        case finished
    }

    let mode: Mode
    /// 0...1 across the floor. The figure walks it; everything to its left is swept.
    let sweptFraction: Double
    /// What the ring has actually come round, 0...1. Equal to `sweptFraction` when counting,
    /// zero while working — the arc carries that state instead.
    let ringFraction: Double

    var isWorking: Bool { mode == .working }
    var isFinished: Bool { mode == .finished }

    static let idle = SweepScene(mode: .working, sweptFraction: 0, ringFraction: 0)

    /// Built from what the deleter reported, and from nothing else.
    static func from(_ progress: DeletionProgress?) -> SweepScene {
        guard let progress else { return .idle }

        if progress.stage == .done {
            return SweepScene(mode: .finished, sweptFraction: 1, ringFraction: 1)
        }

        guard progress.isDeterminate else {
            // Deliberately not `progress.fraction`. It is a true number — some items really
            // have settled — but the run it belongs to cannot be counted through, and a ring
            // that jumped to 87% and then hung there would be worse than one that never
            // claimed a figure at all.
            return SweepScene(mode: .working, sweptFraction: 0, ringFraction: 0)
        }

        let fraction = min(max(progress.fraction, 0), 1)
        return SweepScene(mode: .counting(fraction), sweptFraction: fraction, ringFraction: fraction)
    }

    static let done = SweepScene(mode: .finished, sweptFraction: 1, ringFraction: 1)
}

/// The figure itself, as a set of points in a unit box. Separate from the drawing so the walk
/// can be reasoned about — and tested — without a screenshot.
///
/// Origin is top-left of a 1×1 box; the floor is at `floorY`. The whole thing is scaled by the
/// view, so nothing here carries a point size.
enum SweeperFigure {

    static let floorY: Double = 0.78
    /// How far along the floor the figure may travel. It never reaches the edges: a body drawn
    /// hard against the inside of a ring reads as a mistake.
    static let travel: ClosedRange<Double> = 0.24...0.76

    struct Pose: Equatable {
        let hip: CGPoint
        let shoulder: CGPoint
        let head: CGPoint
        let frontFoot: CGPoint
        let backFoot: CGPoint
        /// Where the hand grips the broom.
        let grip: CGPoint
        /// The two ends of the broom's head, on the floor.
        let broomLeft: CGPoint
        let broomRight: CGPoint
        /// A slight bob, so the walk is not a cut-out sliding along a line.
        let lean: Double
    }

    /// `phase` is 0...1 through one stride. `x` is where along the floor the figure stands.
    static func pose(x: Double, phase: Double, sweeping: Bool) -> Pose {
        let stride = sin(phase * 2 * .pi)
        let bob = abs(cos(phase * .pi)) * 0.012
        let lean = sweeping ? 0.10 + stride * 0.03 : 0.06

        let hipY = floorY - 0.20 - bob
        let hip = CGPoint(x: x, y: hipY)
        let shoulder = CGPoint(x: x + lean * 0.10, y: hipY - 0.12)
        let head = CGPoint(x: shoulder.x + 0.012, y: shoulder.y - 0.055)

        // Legs alternate around the hip. A sweeper leans into the stroke, so the stride is
        // shallower than a walk and the back foot stays planted longer.
        let legSpread = sweeping ? 0.055 : 0.075
        let frontFoot = CGPoint(x: x + legSpread * (0.35 + stride * 0.65), y: floorY)
        let backFoot = CGPoint(x: x - legSpread * (0.35 - stride * 0.65), y: floorY)

        // The broom swings ahead of the body and back under it. This is the only part anyone
        // actually watches, so it gets the widest travel of anything here.
        let swing = sin(phase * 2 * .pi + 0.6)
        let grip = CGPoint(x: shoulder.x + 0.045 + swing * 0.02, y: shoulder.y + 0.055)
        let headCentre = x + 0.11 + swing * 0.075
        let broomLeft = CGPoint(x: headCentre - 0.045, y: floorY)
        let broomRight = CGPoint(x: headCentre + 0.045, y: floorY)

        return Pose(
            hip: hip,
            shoulder: shoulder,
            head: head,
            frontFoot: frontFoot,
            backFoot: backFoot,
            grip: grip,
            broomLeft: broomLeft,
            broomRight: broomRight,
            lean: lean
        )
    }

    /// Where the figure stands for a given scene.
    ///
    /// While the work cannot be counted the figure sweeps on the spot rather than creeping
    /// across — creeping would be the same invented percentage, drawn as a position.
    static func standingX(for scene: SweepScene, workingPhase: Double) -> Double {
        switch scene.mode {
        case .working:
            // A small shuffle around the start, so it reads as work rather than a frozen sprite.
            return travel.lowerBound + sin(workingPhase * 2 * .pi) * 0.02
        case let .counting(fraction):
            return travel.lowerBound + (travel.upperBound - travel.lowerBound) * fraction
        case .finished:
            return travel.upperBound
        }
    }
}

/// The specks on the floor: what has not been swept yet.
///
/// Fixed positions from a fixed seed, so the same deletion draws the same floor every time and
/// a screenshot is comparable with the one before it.
enum SweepFloor {

    /// Each speck's own size. Fourteen identical dots read as a diagram; a floor has grain.
    static func grain(count: Int = 14) -> [CGFloat] {
        (0..<count).map { 1.6 + CGFloat((($0 * 37) % 11)) / 11 * 1.5 }
    }

    /// How many specks the broom has collected by the time it reaches `x`. The heap in front
    /// of it is drawn from this, which makes the pile the same reading as the swept floor — in
    /// a form you watch rather than measure.
    static func collected(by x: Double, count: Int = 14) -> Int {
        specks(count: count).filter { isSwept($0, by: x) }.count
    }

    static func specks(count: Int = 14) -> [CGPoint] {
        var value: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            value ^= value << 13
            value ^= value >> 7
            value ^= value << 17
            return Double(value % 10_000) / 10_000
        }

        return (0..<count).map { index in
            let span = SweeperFigure.travel
            let x = span.lowerBound + (span.upperBound - span.lowerBound + 0.12) * (Double(index) / Double(count)) + next() * 0.03
            return CGPoint(x: x, y: SweeperFigure.floorY - next() * 0.035)
        }
    }

    /// A speck is gone once the broom has passed it.
    static func isSwept(_ speck: CGPoint, by x: Double) -> Bool {
        speck.x < x + 0.07
    }
}
