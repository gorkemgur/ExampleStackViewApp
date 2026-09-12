import XCTest
import DupeCore
@testable import DupeSpace

/// The drawing is the easy half. These hold the half that must not go wrong: the ring never
/// claims a fraction nobody measured, and the swept floor always agrees with it.
@MainActor
final class SweepSceneTests: XCTestCase {

    private func progress(_ stage: DeletionProgress.Stage, settled: Int, total: Int, determinate: Bool) -> DeletionProgress {
        DeletionProgress(stage: stage, settled: settled, total: total, isDeterminate: determinate)
    }

    /// The photo half is one atomic change behind the system's own confirmation. Ninety assets
    /// settle in one instant or none do, so there is no percentage — and a ring that jumped to
    /// 87% and hung there would be worse than one that never claimed a figure.
    func testAnUncountableRunNeverGetsAFraction() {
        let scene = SweepScene.from(progress(.photoLibrary, settled: 78, total: 90, determinate: false))

        XCTAssertTrue(scene.isWorking)
        XCTAssertEqual(scene.ringFraction, 0)
        XCTAssertEqual(scene.sweptFraction, 0)
    }

    func testACountableRunFillsTheRingWithWhatActuallySettled() {
        let scene = SweepScene.from(progress(.files, settled: 3, total: 12, determinate: true))

        XCTAssertEqual(scene.ringFraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(scene.sweptFraction, 0.25, accuracy: 0.0001)
    }

    /// The swept floor *is* the reading, so the two may never disagree — everything left of the
    /// broom is work that really is done.
    func testTheSweptFloorAlwaysAgreesWithTheRing() {
        for settled in 0...12 {
            let scene = SweepScene.from(progress(.files, settled: settled, total: 12, determinate: true))
            XCTAssertEqual(scene.sweptFraction, scene.ringFraction, accuracy: 0.0001)
        }
    }

    func testProgressNeverRunsBackwards() {
        var previous = -1.0
        for settled in 0...12 {
            let scene = SweepScene.from(progress(.files, settled: settled, total: 12, determinate: true))
            XCTAssertGreaterThanOrEqual(scene.ringFraction, previous)
            previous = scene.ringFraction
        }
    }

    func testTheRunEndsCompleteWhateverItReportedOnTheWay() {
        let scene = SweepScene.from(progress(.done, settled: 90, total: 90, determinate: false))

        XCTAssertTrue(scene.isFinished)
        XCTAssertEqual(scene.ringFraction, 1)
    }

    func testNoReportAtAllIsWorkingRatherThanZeroPerCent() {
        XCTAssertTrue(SweepScene.from(nil).isWorking)
    }

    // MARK: - The figure

    /// While nothing can be counted the figure works the spot. Creeping across would be the
    /// same invented percentage, drawn as a position instead of an arc.
    func testTheFigureDoesNotCreepAcrossWhileTheWorkCannotBeCounted() {
        let positions = stride(from: 0.0, to: 1.0, by: 0.1).map {
            SweeperFigure.standingX(for: .idle, workingPhase: $0)
        }

        let span = (positions.max() ?? 0) - (positions.min() ?? 0)
        XCTAssertLessThan(span, 0.06, "it should shuffle on the spot, not walk the floor")
    }

    func testTheFigureWalksTheFloorInStepWithTheCount() {
        let start = SweeperFigure.standingX(
            for: SweepScene.from(progress(.files, settled: 0, total: 10, determinate: true)),
            workingPhase: 0
        )
        let half = SweeperFigure.standingX(
            for: SweepScene.from(progress(.files, settled: 5, total: 10, determinate: true)),
            workingPhase: 0
        )
        let end = SweeperFigure.standingX(
            for: SweepScene.from(progress(.files, settled: 10, total: 10, determinate: true)),
            workingPhase: 0
        )

        XCTAssertEqual(start, SweeperFigure.travel.lowerBound, accuracy: 0.0001)
        XCTAssertEqual(end, SweeperFigure.travel.upperBound, accuracy: 0.0001)
        XCTAssertEqual(half, (start + end) / 2, accuracy: 0.0001)
    }

    /// A body drawn hard against the inside of a ring reads as a mistake, so the walk stays
    /// inside its own bounds at every phase.
    func testTheFigureStaysInsideTheRing() {
        for settled in 0...12 {
            let scene = SweepScene.from(progress(.files, settled: settled, total: 12, determinate: true))
            for phase in stride(from: 0.0, to: 1.0, by: 0.05) {
                let x = SweeperFigure.standingX(for: scene, workingPhase: phase)
                let pose = SweeperFigure.pose(x: x, phase: phase, sweeping: true)
                XCTAssertGreaterThan(pose.backFoot.x, 0.08)
                XCTAssertLessThan(pose.broomRight.x, 0.97)
                XCTAssertGreaterThan(pose.head.y, 0.05)
                XCTAssertLessThan(pose.frontFoot.y, 0.95)
            }
        }
    }

    /// The broom has to be the thing that moves. If its travel is not clearly the widest of
    /// anything in the pose, the figure reads as a sprite sliding along a line.
    func testTheBroomSwingsWiderThanTheBodyMoves() {
        let phases = stride(from: 0.0, to: 1.0, by: 0.02)
        let poses = phases.map { SweeperFigure.pose(x: 0.5, phase: $0, sweeping: true) }

        let broomSwing = (poses.map(\.broomRight.x).max() ?? 0) - (poses.map(\.broomRight.x).min() ?? 0)
        let bodySway = (poses.map(\.shoulder.x).max() ?? 0) - (poses.map(\.shoulder.x).min() ?? 0)

        XCTAssertGreaterThan(broomSwing, bodySway * 2)
        XCTAssertGreaterThan(broomSwing, 0.1)
    }

    // MARK: - The floor

    func testSpecksAheadOfTheBroomSurviveAndSpecksBehindItDoNot() {
        let specks = SweepFloor.specks()
        XCTAssertFalse(specks.isEmpty)

        let x = 0.5
        XCTAssertTrue(specks.filter { $0.x < x - 0.1 }.allSatisfy { SweepFloor.isSwept($0, by: x) })
        XCTAssertTrue(specks.filter { $0.x > x + 0.2 }.allSatisfy { !SweepFloor.isSwept($0, by: x) })
    }

    /// Fixed from a fixed seed, so two runs of the same deletion draw the same floor and a
    /// screenshot is comparable with the one before it.
    func testTheFloorIsTheSameEveryTime() {
        XCTAssertEqual(SweepFloor.specks(), SweepFloor.specks())
    }

    /// The heap in front of the broom is the same reading as the swept floor: it may only ever
    /// grow, and it has to end holding everything the sweep passed.
    func testTheHeapGrowsWithTheSweepAndNeverShrinks() {
        var previous = -1
        for step in 0...20 {
            let x = SweeperFigure.travel.lowerBound
                + (SweeperFigure.travel.upperBound - SweeperFigure.travel.lowerBound) * Double(step) / 20
            let collected = SweepFloor.collected(by: x)
            XCTAssertGreaterThanOrEqual(collected, previous)
            previous = collected
        }
        XCTAssertGreaterThan(previous, 0, "a full sweep has to pick something up")
    }

    /// Fourteen identical dots read as a diagram. A floor has grain.
    func testEverySpeckHasItsOwnSize() {
        let grain = SweepFloor.grain()

        XCTAssertEqual(grain.count, SweepFloor.specks().count)
        XCTAssertGreaterThan(Set(grain).count, 3, "the sizes should vary, not alternate between two")
        XCTAssertTrue(grain.allSatisfy { $0 >= 1.6 && $0 <= 3.2 })
    }

    /// The figure stops at `travel.upperBound`, which is short of the far edge, so the last two
    /// specks sit past where the broom ever reaches. Left as they were, the finished state
    /// showed a tick over a floor that still had dirt on it.
    func testTheFigureNeverReachesTheLastSpecksOnItsOwn() {
        let reach = SweeperFigure.travel.upperBound
        XCTAssertFalse(
            SweepFloor.specks().allSatisfy { SweepFloor.isSwept($0, by: reach) },
            "if this ever passes, the finished state can stop special-casing the floor"
        )
    }
}
