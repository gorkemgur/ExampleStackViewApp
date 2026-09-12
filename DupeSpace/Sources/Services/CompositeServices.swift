import Foundation
import DupeCore

/// Presents the photo library and the granted folders as one library.
///
/// The two have different permission models — photos are all-or-nothing, folders are granted
/// one at a time — so `currentAccess` reports the photo library's state and the folders are
/// simply read whenever there are any. A refused photo library does not stop folder scanning.
final class CompositeMediaLibrary: MediaLibrary {

    private let photos: any MediaLibrary
    private let files: any MediaLibrary

    init(photos: any MediaLibrary, files: any MediaLibrary) {
        self.photos = photos
        self.files = files
    }

    func currentAccess() -> LibraryAccess { photos.currentAccess() }

    func requestAccess() async -> LibraryAccess { await photos.requestAccess() }

    func loadInventory() async throws -> [MediaItem] {
        var items: [MediaItem] = []
        if photos.currentAccess() == .authorized {
            items += try await photos.loadInventory()
        }
        items += try await files.loadInventory()
        return items
    }
}

/// Sends each item to whichever analyzer knows how to read it.
final class CompositeAssetAnalyzer: AssetAnalyzing {

    private let photos: any AssetAnalyzing
    private let files: any AssetAnalyzing

    init(photos: any AssetAnalyzing, files: any AssetAnalyzing) {
        self.photos = photos
        self.files = files
    }

    func contentDigest(for item: MediaItem) async -> ContentDigestResult {
        await analyzer(for: item).contentDigest(for: item)
    }

    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
        await analyzer(for: item).perceptualHashes(for: item)
    }

    private func analyzer(for item: MediaItem) -> any AssetAnalyzing {
        item.source == .fileFolder ? files : photos
    }
}

/// Routes deletions the same way, and reports them as one outcome.
final class CompositeDeleter: MediaDeleting {

    private let photos: any MediaDeleting
    private let files: any MediaDeleting

    init(photos: any MediaDeleting, files: any MediaDeleting) {
        self.photos = photos
        self.files = files
    }

    func delete(ids: [String]) async throws -> DeletionOutcome {
        let fileIDs = ids.filter { FileItemID.isFile($0) }
        let photoIDs = ids.filter { !FileItemID.isFile($0) }

        var deleted: [String] = []

        // Photos first. PhotoKit puts a system prompt in front of its deletion, and file
        // deletions are the half that cannot be undone: dismissing that prompt must not
        // arrive after files have already been removed for good.
        if !photoIDs.isEmpty {
            deleted += try await photos.delete(ids: photoIDs).deletedIDs
        }
        if !fileIDs.isEmpty {
            deleted += try await files.delete(ids: fileIDs).deletedIDs
        }

        return DeletionOutcome(requestedIDs: ids, deletedIDs: deleted)
    }
}
