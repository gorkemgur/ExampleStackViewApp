import Foundation
import Photos
import DupeCore

struct DeletionOutcome: Sendable, Equatable {
    let requestedIDs: [String]
    let deletedIDs: [String]
    /// Files that were deliberately left alone because they no longer matched what the scan
    /// read. Not a failure — a refusal.
    let skippedIDs: [String]
    /// Assets the photo library itself will not let this app delete — synced from a computer,
    /// or belonging to somebody else's shared album. Also a refusal, and a different one: the
    /// scan read them correctly and nothing about them changed. Kept apart from `skippedIDs`
    /// because the sentence the user is shown for the two is not the same sentence.
    let refusedIDs: [String]
    /// Set when part of the work succeeded and part of it did not.
    ///
    /// A deletion that spans the photo library and a Files folder is two operations, and the
    /// second can fail after the first has already happened. Throwing would be a claim that
    /// nothing was deleted, which by then is false, so the outcome carries both halves and the
    /// caller records what went and reports what did not.
    let failure: String?

    init(
        requestedIDs: [String],
        deletedIDs: [String],
        skippedIDs: [String] = [],
        refusedIDs: [String] = [],
        failure: String? = nil
    ) {
        self.requestedIDs = requestedIDs
        self.deletedIDs = deletedIDs
        self.skippedIDs = skippedIDs
        self.refusedIDs = refusedIDs
        self.failure = failure
    }

    var deletedCount: Int { deletedIDs.count }
    var skippedCount: Int { skippedIDs.count }
    var refusedCount: Int { refusedIDs.count }
    /// Items that were asked for but were already gone by the time the change ran.
    var missingCount: Int {
        max(requestedIDs.count - deletedIDs.count - skippedIDs.count - refusedIDs.count, 0)
    }
}

enum DeletionError: LocalizedError, Equatable {
    /// The validator rejected the selection. Nothing was sent to the library.
    case unsafeSelection([String])
    case cancelledByUser
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .unsafeSelection(reasons):
            return "This selection was rejected before anything was deleted: " + reasons.joined(separator: "; ")
        case .cancelledByUser:
            return "Deletion cancelled. Nothing was removed."
        case let .failed(message):
            return message
        }
    }
}

/// How far a deletion has got, honestly.
///
/// The two halves of a deletion report differently and the difference is not a detail. Files
/// are removed one at a time, so each one is a step. The photo library half is a single
/// `PHPhotoLibrary.performChanges`: it is atomic, it is behind a system confirmation the user
/// has to answer, and there is nothing to count through it — ninety assets settle in one
/// instant or none of them do.
///
/// So this carries `isDeterminate` rather than leaving a screen to invent a percentage. A run
/// that is one atomic change says so, and whatever draws it has to be honest about not knowing.
struct DeletionProgress: Sendable, Equatable {

    enum Stage: Sendable, Equatable {
        /// Waiting on the system's own confirmation and the atomic change behind it.
        case photoLibrary
        /// Walking the granted folders, one file at a time.
        case files
        case done
    }

    let stage: Stage
    /// Items whose fate is now settled — deleted, refused or found missing.
    let settled: Int
    let total: Int
    /// False when the whole run is one atomic change and there is nothing to count.
    let isDeterminate: Bool

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(settled) / Double(total), 0), 1)
    }

    static func starting(total: Int, isDeterminate: Bool, stage: Stage) -> DeletionProgress {
        DeletionProgress(stage: stage, settled: 0, total: total, isDeterminate: isDeterminate)
    }
}

/// Called from whatever thread the deletion is running on.
typealias DeletionProgressHandler = @Sendable (DeletionProgress) -> Void

protocol MediaDeleting: Sendable {
    /// `stamps` says what each file looked like when it was scanned. A deleter that can check
    /// must refuse anything that no longer matches; one whose items carry their own identity
    /// through the system — the photo library — can ignore it.
    func delete(ids: [String], expecting stamps: [String: FileStamp]) async throws -> DeletionOutcome

    /// The same work, reporting as it goes. Defaulted, so a deleter with nothing useful to say
    /// about its own progress — which is most of them — does not have to pretend.
    func delete(
        ids: [String],
        expecting stamps: [String: FileStamp],
        onProgress: @escaping DeletionProgressHandler
    ) async throws -> DeletionOutcome
}

extension MediaDeleting {
    func delete(ids: [String]) async throws -> DeletionOutcome {
        try await delete(ids: ids, expecting: [:])
    }

    func delete(
        ids: [String],
        expecting stamps: [String: FileStamp],
        onProgress: @escaping DeletionProgressHandler
    ) async throws -> DeletionOutcome {
        onProgress(.starting(total: ids.count, isDeterminate: false, stage: .photoLibrary))
        let outcome = try await delete(ids: ids, expecting: stamps)
        onProgress(DeletionProgress(stage: .done, settled: ids.count, total: ids.count, isDeterminate: false))
        return outcome
    }
}

/// What the deleter has to know about an asset before it asks Photos to remove it.
///
/// A protocol rather than `PHAsset` itself, because the one decision worth pinning here — which
/// assets may even be sent — is otherwise locked inside a type no test can construct.
protocol DeletableAsset {
    var localIdentifier: String { get }
    var mayBeDeleted: Bool { get }
}

extension PHAsset: DeletableAsset {
    var mayBeDeleted: Bool { canPerform(.delete) }
}

/// Splits the assets a deletion fetched into the ones PhotoKit will accept and the ones it
/// will not.
enum DeletionTriage {

    struct Plan: Equatable {
        /// Sent to `performChanges`.
        let deletable: [String]
        /// Never sent, and never reported as deleted.
        let refused: [String]
    }

    static func plan(_ assets: [some DeletableAsset]) -> Plan {
        var deletable: [String] = []
        var refused: [String] = []
        for asset in assets {
            if asset.mayBeDeleted {
                deletable.append(asset.localIdentifier)
            } else {
                refused.append(asset.localIdentifier)
            }
        }
        return Plan(deletable: deletable, refused: refused)
    }
}

/// Deletes through PhotoKit, which puts a system confirmation in front of the user and moves
/// the assets to Recently Deleted rather than erasing them. Both are features here: the app
/// never destroys anything silently, and a mistake stays recoverable for thirty days.
final class PhotoKitDeleter: MediaDeleting {

    /// `PHPhotosErrorUserCancelled`, spelled as its raw value to avoid depending on a symbol's
    /// availability window.
    private static let userCancelledCode = 3072

    /// Stamps are ignored here, and deliberately: a `PHAsset` identifier follows the asset
    /// through edits and moves, Photos puts its own confirmation in front of the deletion, and
    /// what it removes stays in Recently Deleted for thirty days.
    func delete(ids: [String], expecting _: [String: FileStamp]) async throws -> DeletionOutcome {
        guard !ids.isEmpty else {
            return DeletionOutcome(requestedIDs: [], deletedIDs: [])
        }

        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in assets.append(asset) }

        guard !assets.isEmpty else {
            return DeletionOutcome(requestedIDs: ids, deletedIDs: [])
        }

        let plan = DeletionTriage.plan(assets)

        // Asking for nothing still raises the system confirmation, and answering it would
        // delete nothing. The refusal is the whole answer here.
        guard !plan.deletable.isEmpty else {
            return DeletionOutcome(requestedIDs: ids, deletedIDs: [], refusedIDs: plan.refused)
        }

        let allowed = Set(plan.deletable)
        let requested = assets.filter { allowed.contains($0.localIdentifier) }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(requested as NSArray)
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == PHPhotosErrorDomain && nsError.code == Self.userCancelledCode {
                throw DeletionError.cancelledByUser
            }
            throw DeletionError.failed(error.localizedDescription)
        }

        return DeletionOutcome(requestedIDs: ids, deletedIDs: plan.deletable, refusedIDs: plan.refused)
    }
}

/// Records what it was asked to delete without touching anything.
final class StubDeleter: MediaDeleting, @unchecked Sendable {

    private let lock = NSLock()
    private var _received: [[String]] = []
    private var _expectations: [[String: FileStamp]] = []
    private let behaviour: Behaviour

    enum Behaviour: Sendable {
        case succeed
        /// Deletes everything except the named ids, which come back as refusals — what the real
        /// deleter does with an asset the photo library will not let this app remove.
        case refuse([String])
        case cancel
        case fail(String)
    }

    /// How long to dwell on each item before settling it.
    ///
    /// Zero everywhere except the simulator walk, which needs the deletion to last long enough
    /// to be photographed. A test that waits is a test that is slow for no reason.
    private let stepDelay: Duration

    init(behaviour: Behaviour = .succeed, stepDelay: Duration = .zero) {
        self.behaviour = behaviour
        self.stepDelay = stepDelay
    }

    var received: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return _received
    }

    /// What each call was told to expect, so a test can prove the expectations were passed on
    /// rather than dropped somewhere in the middle.
    var expectations: [[String: FileStamp]] {
        lock.lock(); defer { lock.unlock() }
        return _expectations
    }

    func delete(ids: [String], expecting stamps: [String: FileStamp]) async throws -> DeletionOutcome {
        try await delete(ids: ids, expecting: stamps, onProgress: { _ in })
    }

    func delete(
        ids: [String],
        expecting stamps: [String: FileStamp],
        onProgress: @escaping DeletionProgressHandler
    ) async throws -> DeletionOutcome {
        lock.lock()
        _received.append(ids)
        _expectations.append(stamps)
        lock.unlock()

        switch behaviour {
        case .succeed:
            // Reports the same shape the real composite does, because a stub that reports a
            // different shape is a stub that lets a screen be built against a flow that does
            // not exist. Photo ids settle as one atomic batch; file ids walk.
            let fileIDs = ids.filter { FileItemID.isFile($0) }
            let photoIDs = ids.filter { !FileItemID.isFile($0) }
            let isDeterminate = (photoIDs.isEmpty ? 0 : 1) + fileIDs.count > 1
            var settled = 0

            onProgress(
                .starting(
                    total: ids.count,
                    isDeterminate: isDeterminate,
                    stage: photoIDs.isEmpty ? .files : .photoLibrary
                )
            )

            if !photoIDs.isEmpty {
                // The wait for the system's own confirmation, which is the whole of what the
                // held gate is drawing.
                if stepDelay > .zero { try? await Task.sleep(for: stepDelay * 2) }
                settled = photoIDs.count
                onProgress(
                    DeletionProgress(
                        stage: fileIDs.isEmpty ? .done : .files,
                        settled: settled,
                        total: ids.count,
                        isDeterminate: isDeterminate
                    )
                )
            }

            for _ in fileIDs {
                if stepDelay > .zero { try? await Task.sleep(for: stepDelay) }
                settled += 1
                onProgress(
                    DeletionProgress(stage: .files, settled: settled, total: ids.count, isDeterminate: isDeterminate)
                )
            }

            onProgress(
                DeletionProgress(stage: .done, settled: ids.count, total: ids.count, isDeterminate: isDeterminate)
            )
            return DeletionOutcome(requestedIDs: ids, deletedIDs: ids)
        case let .refuse(refused):
            let refusedSet = Set(refused)
            onProgress(
                DeletionProgress(stage: .done, settled: ids.count, total: ids.count, isDeterminate: false)
            )
            return DeletionOutcome(
                requestedIDs: ids,
                deletedIDs: ids.filter { !refusedSet.contains($0) },
                refusedIDs: ids.filter { refusedSet.contains($0) }
            )
        case .cancel:
            throw DeletionError.cancelledByUser
        case let .fail(message):
            throw DeletionError.failed(message)
        }
    }
}
