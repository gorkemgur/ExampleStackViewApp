import XCTest
import DupeCore
@testable import DupeSpace

private struct RecordingLibrary: MediaLibrary {
    let access: LibraryAccess
    let items: [MediaItem]

    func currentAccess() -> LibraryAccess { access }
    func requestAccess() async -> LibraryAccess { access }
    func loadInventory() async throws -> [MediaItem] { items }
}

/// An actor rather than a lock: these methods run in an async context, where taking a lock is
/// a warning today and an error under the Swift 6 language mode.
private actor RecordingAnalyzer: AssetAnalyzing {

    private let name: String
    private(set) var seen: [String] = []

    init(name: String) { self.name = name }

    func contentDigest(for item: MediaItem) async -> ContentDigestResult {
        seen.append(item.id)
        return .digest(ContentDigest(bytes: Array(name.utf8)))
    }

    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
        seen.append(item.id)
        return nil
    }
}

final class CompositeMediaLibraryTests: XCTestCase {

    private func photo(_ id: String) -> MediaItem {
        MediaItem(id: id, source: .photoLibrary, kind: .image, byteSize: 10)
    }

    private func file(_ id: String) -> MediaItem {
        MediaItem(id: id, source: .fileFolder, kind: .document, byteSize: 10)
    }

    func testMergesBothSourcesWhenPhotosAreAllowed() async throws {
        let library = CompositeMediaLibrary(
            photos: RecordingLibrary(access: .authorized, items: [photo("p1")]),
            files: RecordingLibrary(access: .authorized, items: [file("f1")])
        )
        let items = try await library.loadInventory()
        XCTAssertEqual(items.map(\.id).sorted(), ["f1", "p1"])
    }

    /// The whole point of splitting the two: a refused photo library must not take the
    /// folders down with it.
    func testGrantedFoldersAreStillReadWhenPhotosAreRefused() async throws {
        let library = CompositeMediaLibrary(
            photos: RecordingLibrary(access: .denied, items: [photo("p1")]),
            files: RecordingLibrary(access: .authorized, items: [file("f1")])
        )
        let items = try await library.loadInventory()
        XCTAssertEqual(items.map(\.id), ["f1"])
    }

    func testLimitedPhotoAccessReadsNoPhotos() async throws {
        let library = CompositeMediaLibrary(
            photos: RecordingLibrary(access: .limited, items: [photo("p1")]),
            files: RecordingLibrary(access: .authorized, items: [])
        )
        let items = try await library.loadInventory()
        XCTAssertTrue(items.isEmpty)
    }

    func testAccessReportsThePhotoLibraryState() {
        let library = CompositeMediaLibrary(
            photos: RecordingLibrary(access: .notDetermined, items: []),
            files: RecordingLibrary(access: .authorized, items: [])
        )
        XCTAssertEqual(library.currentAccess(), .notDetermined)
    }
}

final class CompositeAnalyzerTests: XCTestCase {

    func testEachItemGoesToTheAnalyzerThatCanReadIt() async {
        let photos = RecordingAnalyzer(name: "photos")
        let files = RecordingAnalyzer(name: "files")
        let analyzer = CompositeAssetAnalyzer(photos: photos, files: files)

        _ = await analyzer.contentDigest(
            for: MediaItem(id: "p1", source: .photoLibrary, kind: .image)
        )
        _ = await analyzer.contentDigest(
            for: MediaItem(id: "f1", source: .fileFolder, kind: .document)
        )

        let photosSeen = await photos.seen
        let filesSeen = await files.seen
        XCTAssertEqual(photosSeen, ["p1"])
        XCTAssertEqual(filesSeen, ["f1"])
    }
}

final class CompositeDeleterTests: XCTestCase {

    private let photoID = "ABC123/L0/001"
    private var fileID: String { FileItemID.make(folderID: UUID(), relativePath: "a.txt") }

    func testEachIdentifierGoesToTheRightDeleter() async throws {
        let photos = StubDeleter()
        let files = StubDeleter()
        let file = fileID

        let outcome = try await CompositeDeleter(photos: photos, files: files)
            .delete(ids: [photoID, file])

        XCTAssertEqual(photos.received, [[photoID]])
        XCTAssertEqual(files.received, [[file]])
        XCTAssertEqual(Set(outcome.deletedIDs), [photoID, file])
    }

    /// Photo deletion shows a system prompt. Dismissing it must not arrive after files have
    /// already been removed for good.
    func testCancellingThePhotoPromptLeavesFilesUntouched() async {
        let photos = StubDeleter(behaviour: .cancel)
        let files = StubDeleter()

        do {
            _ = try await CompositeDeleter(photos: photos, files: files)
                .delete(ids: [photoID, fileID])
            XCTFail("a cancelled deletion must not report success")
        } catch {
            XCTAssertTrue(files.received.isEmpty, "nothing irreversible may happen before the prompt is answered")
        }
    }

    func testOnlyFilesSelectedNeverTouchesThePhotoLibrary() async throws {
        let photos = StubDeleter()
        let files = StubDeleter()

        _ = try await CompositeDeleter(photos: photos, files: files).delete(ids: [fileID])

        XCTAssertTrue(photos.received.isEmpty)
        XCTAssertEqual(files.received.count, 1)
    }

    func testAnEmptySelectionAsksNobodyToDeleteAnything() async throws {
        let photos = StubDeleter()
        let files = StubDeleter()

        let outcome = try await CompositeDeleter(photos: photos, files: files).delete(ids: [])

        XCTAssertTrue(photos.received.isEmpty)
        XCTAssertTrue(files.received.isEmpty)
        XCTAssertTrue(outcome.deletedIDs.isEmpty)
    }
}
