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

    // MARK: - Progress that does not lie

    /// A screen may only draw a measurement it was actually given. The photo half is one
    /// atomic `performChanges` behind a system prompt: ninety assets settle in one instant or
    /// none of them do, so a run made entirely of photos has nothing to count through and says
    /// so. Anything drawing a bar creeping across during it would be animating, not measuring.
    func testAPhotoOnlyDeletionReportsThatItCannotBeCounted() async throws {
        let steps = ProgressRecorder()

        _ = try await CompositeDeleter(photos: StubDeleter(), files: StubDeleter())
            .delete(ids: [photoID, "DEF456/L0/001"], expecting: [:], onProgress: steps.record)

        let seen = steps.steps
        XCTAssertFalse(seen.isEmpty)
        XCTAssertTrue(seen.allSatisfy { !$0.isDeterminate }, "one atomic change is not a progress bar")
        XCTAssertEqual(seen.last?.stage, .done)
        XCTAssertEqual(seen.last?.settled, 2)
    }

    /// Files are a loop, and every turn of it removes something for good. That half can be
    /// counted, and it has to be counted only after each file's fate is settled.
    func testAFileDeletionCountsUpOneAtATime() async throws {
        let steps = ProgressRecorder()
        let ids = (0..<4).map { _ in fileID }

        _ = try await CompositeDeleter(photos: StubDeleter(), files: StubDeleter())
            .delete(ids: ids, expecting: [:], onProgress: steps.record)

        let seen = steps.steps
        XCTAssertTrue(seen.contains { $0.isDeterminate })
        XCTAssertEqual(seen.last?.settled, 4)
        XCTAssertEqual(seen.last?.total, 4)
        XCTAssertEqual(
            seen.map(\.settled),
            seen.map(\.settled).sorted(),
            "progress may never run backwards"
        )
        XCTAssertTrue(seen.allSatisfy { $0.settled <= $0.total }, "more settled than requested is not a state")
    }

    /// The mixed case: the photo batch lands as one jump of however many assets it held, and
    /// the files tick after it.
    func testAMixedDeletionJumpsThroughThePhotosThenWalksTheFiles() async throws {
        let steps = ProgressRecorder()
        let files = (0..<3).map { _ in fileID }

        _ = try await CompositeDeleter(photos: StubDeleter(), files: StubDeleter())
            .delete(ids: [photoID] + files, expecting: [:], onProgress: steps.record)

        let seen = steps.steps
        XCTAssertTrue(seen.contains { $0.stage == .photoLibrary })
        XCTAssertTrue(seen.contains { $0.stage == .files })
        XCTAssertEqual(seen.last?.stage, .done)
        XCTAssertEqual(seen.last?.settled, 4)
        XCTAssertEqual(
            seen.map(\.settled),
            seen.map(\.settled).sorted(),
            "progress may never run backwards"
        )
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

/// Collects what a deleter reported, from whatever thread it reported on.
private final class ProgressRecorder: @unchecked Sendable {

    private let lock = NSLock()
    private var _steps: [DeletionProgress] = []

    var steps: [DeletionProgress] {
        lock.lock(); defer { lock.unlock() }
        return _steps
    }

    var record: DeletionProgressHandler {
        { [self] step in
            lock.lock(); _steps.append(step); lock.unlock()
        }
    }
}
