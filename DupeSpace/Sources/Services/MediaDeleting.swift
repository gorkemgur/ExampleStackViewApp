import Foundation
import Photos
import DupeCore

struct DeletionOutcome: Sendable, Equatable {
    let requestedIDs: [String]
    let deletedIDs: [String]
    /// Files that were deliberately left alone because they no longer matched what the scan
    /// read. Not a failure — a refusal.
    let skippedIDs: [String]
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
        failure: String? = nil
    ) {
        self.requestedIDs = requestedIDs
        self.deletedIDs = deletedIDs
        self.skippedIDs = skippedIDs
        self.failure = failure
    }

    var deletedCount: Int { deletedIDs.count }
    var skippedCount: Int { skippedIDs.count }
    /// Items that were asked for but were already gone by the time the change ran.
    var missingCount: Int {
        max(requestedIDs.count - deletedIDs.count - skippedIDs.count, 0)
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

        let identifiers = assets.map(\.localIdentifier)

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == PHPhotosErrorDomain && nsError.code == Self.userCancelledCode {
                throw DeletionError.cancelledByUser
            }
            throw DeletionError.failed(error.localizedDescription)
        }

        return DeletionOutcome(requestedIDs: ids, deletedIDs: identifiers)
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
            onProgress(.starting(total: ids.count, isDeterminate: ids.count > 1, stage: .files))
            for (index, _) in ids.enumerated() {
                if stepDelay > .zero { try? await Task.sleep(for: stepDelay) }
                onProgress(
                    DeletionProgress(
                        stage: .files,
                        settled: index + 1,
                        total: ids.count,
                        isDeterminate: ids.count > 1
                    )
                )
            }
            onProgress(
                DeletionProgress(stage: .done, settled: ids.count, total: ids.count, isDeterminate: ids.count > 1)
            )
            return DeletionOutcome(requestedIDs: ids, deletedIDs: ids)
        case .cancel:
            throw DeletionError.cancelledByUser
        case let .fail(message):
            throw DeletionError.failed(message)
        }
    }
}
