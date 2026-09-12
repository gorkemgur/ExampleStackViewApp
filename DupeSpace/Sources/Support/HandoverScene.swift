import CoreGraphics
import Foundation
import DupeCore

/// The deletion, drawn as geometry: two lanes, a gate, and what sits beyond it.
///
/// Every number the instrument draws is decided here, in a type with no SwiftUI in it, because
/// the thing that must not be got wrong is not how it looks — it is that it never claims to
/// know something the deleter did not tell it.
///
/// The shape states the safety model without a word:
///
/// - The **photo lane is one block**, because the photo half is a single
///   `PHPhotoLibrary.performChanges`. It is atomic: ninety assets settle in one instant or none
///   do. It never subdivides, never creeps, never counts.
/// - The **file lane is discrete cells**, because that half is a loop over real `removeItem`
///   calls, and each turn of it destroys something for good. It empties one notch per callback.
/// - Beyond the gate there is a **hold**, and only the photo lane reaches it: that is Recently
///   Deleted, thirty days, space that is not yours yet. The file lane has nothing beyond the
///   gate, and that absence is the message.
///
/// Countable work is drawn as countable pieces; atomic work is drawn as one piece. A screen
/// that animated the photo half item by item would be inventing a measurement, which is the one
/// thing this app has refused to do everywhere else.
struct HandoverScene: Equatable {

    struct Lane: Equatable, Identifiable {

        enum Kind: String, Equatable {
            case photos
            case files
        }

        let kind: Kind
        /// This lane's share of the staging width. Lanes sum to 1 when anything is staged.
        let widthShare: Double
        /// Zero when the lane is atomic and there is nothing to count.
        let cellCount: Int
        /// Above 1 only when there are more files than cells the width can hold.
        let itemsPerCell: Int
        let settledCells: Int
        /// Files the deleter refused — reinstated once the outcome is known, never guessed at
        /// while the work is in flight.
        let refusedCells: Int
        let hasCrossed: Bool
        /// What is parked beyond the gate, as a share of the whole instrument. Zero unless this
        /// lane's deletions go to Recently Deleted.
        let holdShare: Double

        var id: String { kind.rawValue }
        var isAtomic: Bool { cellCount == 0 }
    }

    let lanes: [Lane]
    /// True while nothing can be reported: the system's own confirmation is up, or the atomic
    /// change has not returned. The gate is the only thing allowed to move.
    let gateIsHeld: Bool
    let stage: DeletionProgress.Stage

    var isEmpty: Bool { lanes.isEmpty }
    var hasHold: Bool { lanes.contains { $0.holdShare > 0 } }

    // MARK: - The three states

    /// Everything staged, nothing crossed. What the instrument looks like the instant the red
    /// key is spent.
    static func staged(savings: SavingsBreakdown, fileCount: Int, width: CGFloat) -> HandoverScene {
        build(
            savings: savings,
            fileCount: fileCount,
            width: width,
            settledFiles: 0,
            refusedFiles: 0,
            photosHaveCrossed: false,
            gateIsHeld: true,
            stage: .photoLibrary
        )
    }

    /// The work in flight, as the deleter reports it.
    ///
    /// `settledFiles` is derived from what actually came back, and it is clamped rather than
    /// trusted: a report that ran ahead of the file count would draw cells emptying that no
    /// callback had settled.
    static func inFlight(
        progress: DeletionProgress,
        savings: SavingsBreakdown,
        fileCount: Int,
        photoCount: Int,
        width: CGFloat
    ) -> HandoverScene {
        let photosDone = progress.stage != .photoLibrary
        let settledFiles = photosDone ? max(progress.settled - photoCount, 0) : 0

        return build(
            savings: savings,
            fileCount: fileCount,
            width: width,
            settledFiles: min(settledFiles, fileCount),
            refusedFiles: 0,
            photosHaveCrossed: photosDone,
            // Held for the whole of the atomic half, and only that half. Once the files start
            // ticking there is a real reading to draw and the loop has nothing left to say.
            gateIsHeld: !photosDone,
            stage: progress.stage
        )
    }

    /// Arrived. Every file crossed, every refusal reinstated, nothing moving.
    static func settled(outcome: DeletionOutcome, savings: SavingsBreakdown, fileCount: Int, width: CGFloat) -> HandoverScene {
        build(
            savings: savings,
            fileCount: fileCount,
            width: width,
            settledFiles: fileCount,
            refusedFiles: min(outcome.skippedCount, fileCount),
            photosHaveCrossed: true,
            gateIsHeld: false,
            stage: .done
        )
    }

    // MARK: - Building one

    private static func build(
        savings: SavingsBreakdown,
        fileCount: Int,
        width: CGFloat,
        settledFiles: Int,
        refusedFiles: Int,
        photosHaveCrossed: Bool,
        gateIsHeld: Bool,
        stage: DeletionProgress.Stage
    ) -> HandoverScene {

        // `cloudOnlyBytes` is excluded from both lanes and from the hold, deliberately. Those
        // originals were never on this device, so nothing about them crosses anything; drawing
        // them would be the instrument claiming to free local space it cannot free.
        let deferred = max(savings.deferredBytes, 0)
        let immediate = max(savings.immediateBytes, 0)
        let onDevice = deferred + immediate

        guard onDevice > 0 else {
            return HandoverScene(lanes: [], gateIsHeld: gateIsHeld, stage: stage)
        }

        var lanes: [Lane] = []

        if deferred > 0 {
            let share = Double(deferred) / Double(onDevice)
            lanes.append(
                Lane(
                    kind: .photos,
                    widthShare: share,
                    cellCount: 0,
                    itemsPerCell: 1,
                    settledCells: 0,
                    refusedCells: 0,
                    hasCrossed: photosHaveCrossed,
                    // Photos go to Recently Deleted, so the hold is exactly this lane's share.
                    // A files-only deletion draws nothing beyond the gate at all.
                    holdShare: share
                )
            )
        }

        if immediate > 0 {
            let share = Double(immediate) / Double(onDevice)
            let layout = HandoverLayout.cells(count: max(fileCount, 1), in: width * share)
            lanes.append(
                Lane(
                    kind: .files,
                    widthShare: share,
                    cellCount: layout.cellCount,
                    itemsPerCell: layout.itemsPerCell,
                    settledCells: cells(forItems: settledFiles, layout: layout),
                    refusedCells: cells(forItems: refusedFiles, layout: layout),
                    hasCrossed: settledFiles >= fileCount && fileCount > 0,
                    holdShare: 0
                )
            )
        }

        return HandoverScene(lanes: lanes, gateIsHeld: gateIsHeld, stage: stage)
    }

    /// Items to whole cells, rounded down.
    ///
    /// Down, not up or to nearest: a partly-consumed cell must not read as consumed. With ten
    /// files to a cell, one deleted file emptying a cell would be the instrument claiming nine
    /// deletions that have not happened.
    private static func cells(forItems items: Int, layout: HandoverLayout.Result) -> Int {
        guard items > 0, layout.itemsPerCell > 0 else { return 0 }
        return min(items / layout.itemsPerCell, layout.cellCount)
    }
}

/// How many cells fit, and how many files each one therefore stands for.
enum HandoverLayout {

    struct Result: Equatable {
        let cellCount: Int
        let itemsPerCell: Int
    }

    static let minimumCellWidth: CGFloat = 5
    static let gap: CGFloat = 3

    /// One cell per file while they fit, and a fixed number of files per cell once they do not.
    ///
    /// A hundred and seventy files at one cell each would be sub-pixel slivers, so past the
    /// point where a cell would fall below `minimumCellWidth` the lane switches to a coarser
    /// grain and each cell stands for several files. The instrument then moves in steps of that
    /// many, which is still a reading — just a coarser one — rather than a smooth crawl that
    /// would imply a precision the lane does not have.
    static func cells(
        count: Int,
        in width: CGFloat,
        minimumCellWidth: CGFloat = HandoverLayout.minimumCellWidth,
        gap: CGFloat = HandoverLayout.gap
    ) -> Result {
        guard count > 0, width > 0 else { return Result(cellCount: 0, itemsPerCell: 1) }

        let capacity = max(Int((width + gap) / (minimumCellWidth + gap)), 1)
        if count <= capacity {
            return Result(cellCount: count, itemsPerCell: 1)
        }

        let itemsPerCell = Int((Double(count) / Double(capacity)).rounded(.up))
        let cellCount = Int((Double(count) / Double(itemsPerCell)).rounded(.up))
        return Result(cellCount: max(cellCount, 1), itemsPerCell: max(itemsPerCell, 1))
    }
}
