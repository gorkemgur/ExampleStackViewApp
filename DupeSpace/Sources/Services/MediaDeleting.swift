import Foundation
import Photos
import DupeCore

struct DeletionOutcome: Sendable, Equatable {
    let requestedIDs: [String]
    let deletedIDs: [String]
    /// Files that were deliberately left alone because they no longer matched what the scan
    /// read. Not a failure — a refusal.
    let skippedIDs: [String]

    init(requestedIDs: [String], deletedIDs: [String], skippedIDs: [String] = []) {
        self.requestedIDs = requestedIDs
        self.deletedIDs = deletedIDs
        self.skippedIDs = skippedIDs
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

protocol MediaDeleting: Sendable {
    /// `stamps` says what each file looked like when it was scanned. A deleter that can check
    /// must refuse anything that no longer matches; one whose items carry their own identity
    /// through the system — the photo library — can ignore it.
    func delete(ids: [String], expecting stamps: [String: FileStamp]) async throws -> DeletionOutcome
}

extension MediaDeleting {
    func delete(ids: [String]) async throws -> DeletionOutcome {
        try await delete(ids: ids, expecting: [:])
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

    init(behaviour: Behaviour = .succeed) {
        self.behaviour = behaviour
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
        lock.lock()
        _received.append(ids)
        _expectations.append(stamps)
        lock.unlock()

        switch behaviour {
        case .succeed:
            return DeletionOutcome(requestedIDs: ids, deletedIDs: ids)
        case .cancel:
            throw DeletionError.cancelledByUser
        case let .fail(message):
            throw DeletionError.failed(message)
        }
    }
}
