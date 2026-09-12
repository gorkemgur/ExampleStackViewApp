import XCTest
import DupeCore
@testable import DupeSpace

/// These assert the honesty of the deletion instrument, not its looks.
///
/// The whole design rests on one claim: it never draws a measurement the deleter did not give
/// it. That claim is worth exactly as much as the test that holds it, so it is written as one.
@MainActor
final class HandoverSceneTests: XCTestCase {

    private let width: CGFloat = 320

    private func savings(immediate: Int64 = 0, deferred: Int64 = 0, cloud: Int64 = 0) -> SavingsBreakdown {
        SavingsBreakdown(
            immediateBytes: immediate,
            deferredBytes: deferred,
            cloudOnlyBytes: cloud,
            itemCount: 1,
            bytesByKind: [:]
        )
    }

    private func progress(_ stage: DeletionProgress.Stage, settled: Int, total: Int, determinate: Bool) -> DeletionProgress {
        DeletionProgress(stage: stage, settled: settled, total: total, isDeterminate: determinate)
    }

    // MARK: - The no-fabrication invariant

    /// The photo half is one atomic change behind a system prompt. Until it returns, nothing has
    /// settled, and nothing in the picture may say otherwise.
    func testNothingSettlesWhileThePhotoHalfIsInFlight() {
        let scene = HandoverScene.inFlight(
            progress: progress(.photoLibrary, settled: 0, total: 90, determinate: false),
            savings: savings(immediate: 1_000, deferred: 9_000),
            fileCount: 12,
            photoCount: 78,
            width: width
        )

        XCTAssertTrue(scene.gateIsHeld, "the gate is the only thing allowed to move while nothing can be reported")
        for lane in scene.lanes {
            XCTAssertEqual(lane.settledCells, 0, "\(lane.kind) drew settled work during the atomic half")
            XCTAssertFalse(lane.hasCrossed)
        }
    }

    /// And a photo-only run never gets cells at all. There is no per-item motion to draw,
    /// however much a screen would like some.
    func testThePhotoLaneIsAlwaysOneBlock() {
        let scene = HandoverScene.staged(savings: savings(deferred: 9_000), fileCount: 0, width: width)

        XCTAssertEqual(scene.lanes.count, 1)
        XCTAssertTrue(scene.lanes[0].isAtomic)
        XCTAssertEqual(scene.lanes[0].cellCount, 0)
    }

    /// Files are a loop over real removals, so that half is counted — and only after the photos
    /// have settled, because the file loop has not started before then.
    func testTheFileLaneCountsOnceThePhotosHaveSettled() {
        let scene = HandoverScene.inFlight(
            progress: progress(.files, settled: 78 + 5, total: 90, determinate: true),
            savings: savings(immediate: 5_000, deferred: 5_000),
            fileCount: 12,
            photoCount: 78,
            width: width
        )

        let files = scene.lanes.first { $0.kind == .files }
        XCTAssertEqual(files?.settledCells, 5)
        XCTAssertFalse(scene.gateIsHeld)
    }

    /// A report that ran ahead of the file count would empty cells no callback had settled.
    func testSettledCellsCanNeverExceedTheLane() {
        let scene = HandoverScene.inFlight(
            progress: progress(.files, settled: 9_999, total: 12, determinate: true),
            savings: savings(immediate: 5_000),
            fileCount: 12,
            photoCount: 0,
            width: width
        )

        let files = scene.lanes.first { $0.kind == .files }
        XCTAssertEqual(files?.settledCells, files?.cellCount)
    }

    /// Never backwards. A stutter here reads as the app undoing a deletion, which it cannot do.
    func testProgressNeverRunsBackwards() {
        var previous = 0
        for settled in 0...12 {
            let scene = HandoverScene.inFlight(
                progress: progress(.files, settled: settled, total: 12, determinate: true),
                savings: savings(immediate: 5_000),
                fileCount: 12,
                photoCount: 0,
                width: width
            )
            let cells = scene.lanes.first { $0.kind == .files }?.settledCells ?? 0
            XCTAssertGreaterThanOrEqual(cells, previous)
            previous = cells
        }
    }

    // MARK: - What the geometry says

    /// The two lanes share one denominator, so their widths say which half of this deletion is
    /// the big one.
    func testLaneWidthsAreTheByteShares() {
        let scene = HandoverScene.staged(
            savings: savings(immediate: 2_500, deferred: 7_500),
            fileCount: 4,
            width: width
        )

        let photos = scene.lanes.first { $0.kind == .photos }
        let files = scene.lanes.first { $0.kind == .files }
        XCTAssertEqual(photos?.widthShare ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(files?.widthShare ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(scene.lanes.reduce(0) { $0 + $1.widthShare }, 1, accuracy: 0.001)
    }

    /// An original that was only ever in iCloud never left this device, so nothing about it may
    /// be drawn crossing anything. Including it would be the instrument claiming to free local
    /// space it cannot free.
    func testCloudOnlyBytesAreDrawnNowhere() {
        let scene = HandoverScene.staged(
            savings: savings(immediate: 1_000, cloud: 9_000_000),
            fileCount: 2,
            width: width
        )

        XCTAssertEqual(scene.lanes.count, 1)
        XCTAssertEqual(scene.lanes[0].kind, .files)
        XCTAssertFalse(scene.hasHold)
    }

    /// The hold is Recently Deleted. A files-only deletion has nothing beyond the gate, and
    /// that absence is the message — it is also what keeps the wrong sentence from appearing
    /// under the wrong picture.
    func testTheHoldExistsOnlyWhenSomethingGoesToRecentlyDeleted() {
        let photos = HandoverScene.staged(savings: savings(deferred: 9_000), fileCount: 0, width: width)
        let files = HandoverScene.staged(savings: savings(immediate: 9_000), fileCount: 6, width: width)

        XCTAssertTrue(photos.hasHold)
        XCTAssertFalse(files.hasHold)
        XCTAssertTrue(files.lanes.allSatisfy { $0.holdShare == 0 })
    }

    /// A deletion made entirely of cloud-only originals frees nothing on this device, so there
    /// is nothing to draw. Better an empty instrument than one inventing cargo.
    func testNothingOnTheDeviceDrawsNothing() {
        let scene = HandoverScene.staged(savings: savings(cloud: 9_000), fileCount: 0, width: width)

        XCTAssertTrue(scene.isEmpty)
    }

    // MARK: - Arrival

    func testTheSettledSceneReinstatesRefusals() {
        let outcome = DeletionOutcome(
            requestedIDs: Array(repeating: "x", count: 12),
            deletedIDs: Array(repeating: "x", count: 9),
            skippedIDs: ["a", "b", "c"]
        )
        let scene = HandoverScene.settled(
            outcome: outcome,
            savings: savings(immediate: 5_000),
            fileCount: 12,
            width: width
        )

        let files = scene.lanes.first { $0.kind == .files }
        XCTAssertEqual(files?.refusedCells, 3)
        XCTAssertEqual(scene.stage, .done)
        XCTAssertFalse(scene.gateIsHeld, "nothing may loop after the work is finished")
    }

    // MARK: - Layout

    /// A hundred and seventy files at one cell each would be sub-pixel slivers. Past the width's
    /// capacity the lane goes coarser rather than thinner.
    func testCellsCoarsenRatherThanShrinkBelowLegibility() {
        let many = HandoverLayout.cells(count: 400, in: 200)

        XCTAssertGreaterThan(many.itemsPerCell, 1)
        XCTAssertGreaterThanOrEqual(many.cellCount * many.itemsPerCell, 400)
        XCTAssertLessThanOrEqual(
            CGFloat(many.cellCount) * HandoverLayout.minimumCellWidth,
            200 + CGFloat(many.cellCount) * HandoverLayout.gap
        )
    }

    func testAFewFilesGetOneCellEach() {
        let few = HandoverLayout.cells(count: 6, in: 200)

        XCTAssertEqual(few.cellCount, 6)
        XCTAssertEqual(few.itemsPerCell, 1)
    }

    /// Rounded down, always. With ten files to a cell, one deleted file emptying a cell would
    /// be the instrument claiming nine deletions that have not happened.
    func testAPartlyConsumedCellIsNotDrawnAsConsumed() {
        let scene = HandoverScene.inFlight(
            progress: progress(.files, settled: 9, total: 400, determinate: true),
            savings: savings(immediate: 5_000),
            fileCount: 400,
            photoCount: 0,
            width: 200
        )

        let files = scene.lanes.first { $0.kind == .files }
        XCTAssertEqual(files?.settledCells, 0, "nine files out of a ten-file cell is not a settled cell")
    }
}
