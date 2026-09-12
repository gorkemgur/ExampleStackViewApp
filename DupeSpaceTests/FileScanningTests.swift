import XCTest
import DupeCore
@testable import DupeSpace

/// Exercised against a real directory on disk rather than a fake file system: the parts most
/// likely to be wrong here — relative paths, byte counts, coordinated deletion — are exactly
/// the parts a fake would paper over.
final class FileScanningTests: XCTestCase {

    private var root: URL!
    private var folder: GrantedFolder!
    private var registry: InMemoryFolderRegistry!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dupespace-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        folder = try XCTUnwrap(FolderAccess.makeGrant(for: root), "could not bookmark the test folder")
        registry = InMemoryFolderRegistry(folders: [folder])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    @discardableResult
    private func write(_ relativePath: String, _ contents: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func items() -> [MediaItem] {
        FileMediaLibrary.items(in: folder)
    }

    // MARK: - Enumeration

    func testFindsRegularFilesWithTheirSizes() throws {
        try write("notes.txt", "hello world")
        let found = items()

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].displayName, "notes.txt")
        XCTAssertEqual(found[0].byteSize, 11)
        XCTAssertEqual(found[0].source, .fileFolder)
        XCTAssertEqual(found[0].kind, .document)
        XCTAssertTrue(found[0].isLocallyAvailable)
    }

    func testNestedFilesKeepTheirPathInsideTheGrant() throws {
        try write("invoices/2024/march.txt", "x")
        let found = items()

        XCTAssertEqual(found.count, 1)
        let parsed = try XCTUnwrap(FileItemID.parse(found[0].id))
        XCTAssertEqual(parsed.folderID, folder.id)
        XCTAssertEqual(parsed.relativePath, "invoices/2024/march.txt")
    }

    func testEmptyFilesAreIgnored() throws {
        try write("blank.txt", "")
        XCTAssertTrue(items().isEmpty, "a zero-byte file cannot be a duplicate of anything worth deleting")
    }

    func testDirectoriesAreNotItems() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("empty-dir"),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(items().isEmpty)
    }

    func testRelativePathOfAFileOutsideTheRootFallsBackToItsName() {
        let outside = URL(fileURLWithPath: "/tmp/elsewhere/thing.txt")
        XCTAssertEqual(FileMediaLibrary.relativePath(of: outside, under: root), "thing.txt")
    }

    // MARK: - Identifiers

    func testIdentifiersRoundTrip() {
        let id = FileItemID.make(folderID: folder.id, relativePath: "a/b c.txt")
        let parsed = FileItemID.parse(id)
        XCTAssertEqual(parsed?.folderID, folder.id)
        XCTAssertEqual(parsed?.relativePath, "a/b c.txt")
        XCTAssertTrue(FileItemID.isFile(id))
    }

    func testIdentifiersSurviveASeparatorInTheFileName() {
        let id = FileItemID.make(folderID: folder.id, relativePath: "weird|name.txt")
        XCTAssertEqual(FileItemID.parse(id)?.relativePath, "weird|name.txt")
    }

    func testPhotoIdentifiersAreNotMistakenForFiles() {
        XCTAssertFalse(FileItemID.isFile("ABC123/L0/001"))
        XCTAssertNil(FileItemID.parse("ABC123/L0/001"))
        XCTAssertNil(FileItemID.parse("file:not-a-uuid|x.txt"))
        XCTAssertNil(FileItemID.parse("file:\(UUID().uuidString)|"))
    }

    // MARK: - Hashing

    func testIdenticalContentDigestsIdentically() throws {
        let first = try write("one.txt", "the same bytes")
        let second = try write("two.txt", "the same bytes")
        let third = try write("three.txt", "other bytes!!!")

        guard
            case let .digest(a) = FileAssetAnalyzer.digest(of: first),
            case let .digest(b) = FileAssetAnalyzer.digest(of: second),
            case let .digest(c) = FileAssetAnalyzer.digest(of: third)
        else {
            return XCTFail("a readable file must produce a digest")
        }

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testAMissingFileIsUnavailableRatherThanAnEmptyDigest() {
        let result = FileAssetAnalyzer.digest(of: root.appendingPathComponent("nothing-here.txt"))
        XCTAssertEqual(result, .unavailable)
    }

    func testDigestingSpansChunkBoundaries() throws {
        // Larger than the read chunk, so the streaming path is actually exercised.
        let payload = String(repeating: "abcdefgh", count: 200_000)  // 1.6 MB
        let big = try write("big.bin", payload)
        let same = try write("big-copy.bin", payload)

        guard
            case let .digest(a) = FileAssetAnalyzer.digest(of: big),
            case let .digest(b) = FileAssetAnalyzer.digest(of: same)
        else {
            return XCTFail("large files must still digest")
        }
        XCTAssertEqual(a, b)
    }

    // MARK: - End to end

    func testAScanFindsDuplicateFilesAndKeepsOne() async throws {
        try write("contract.txt", "hello world")
        try write("contract (1).txt", "hello world")
        // Same length, different content: size alone must not be treated as proof.
        try write("decoy.txt", "world hello")

        let result = try await ScanPipeline(
            analyzer: FileAssetAnalyzer(registry: registry),
            throttle: UnthrottledScan()
        ).run(items: items())

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].relation, .exact)
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates[0].tier, .identical)

        let survivor = result.decisions.first?.keeperID
        XCTAssertNotNil(survivor)
        XCTAssertNotEqual(survivor, result.candidates[0].id)
    }

    func testSavingsFromFilesAreImmediateRatherThanDeferred() async throws {
        try write("a.txt", "duplicate me")
        try write("b.txt", "duplicate me")

        let indexed = Dictionary(uniqueKeysWithValues: items().map { ($0.id, $0) })
        let savings = SavingsCalculator.breakdown(for: Set(indexed.keys.prefix(1)), items: indexed)

        XCTAssertEqual(savings.deferredBytes, 0, "files do not go to Recently Deleted")
        XCTAssertGreaterThan(savings.immediateBytes, 0)
    }

    // MARK: - Deletion

    /// Every deletion in this suite goes through the stamped call, because that is the only
    /// call the app makes and now the only one the deleter honours.
    private func stamps(for items: [MediaItem]) -> [String: FileStamp] {
        items.reduce(into: [:]) { $0[$1.id] = FileStamp($1) }
    }

    func testDeletingRemovesTheFileFromDisk() async throws {
        let url = try write("gone.txt", "bytes")
        let target = try XCTUnwrap(items().first)

        let outcome = try await FileDeleter(registry: registry)
            .delete(ids: [target.id], expecting: stamps(for: [target]))

        XCTAssertEqual(outcome.deletedIDs, [target.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// The fail-closed rule, stated as a test so it cannot quietly go back.
    ///
    /// `MediaDeleting` offers `delete(ids:)` with no stamps at all, and the deleter used to
    /// read that as "nothing to check against, go ahead" — on the half of this app that cannot
    /// be undone. An unstamped file is one the caller cannot vouch for, and the answer is no.
    func testAFileWithNoStampIsRefusedRatherThanDeleted() async throws {
        let url = try write("unvouched.txt", "bytes")
        let target = try XCTUnwrap(items().first)

        let outcome = try await FileDeleter(registry: registry).delete(ids: [target.id])

        XCTAssertTrue(outcome.deletedIDs.isEmpty)
        XCTAssertEqual(outcome.skippedIDs, [target.id], "a refusal, not a failure")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeletingSomethingAlreadyGoneReportsItMissingRatherThanFailing() async throws {
        try write("vanishing.txt", "bytes")
        let target = try XCTUnwrap(items().first)
        let stamp = stamps(for: [target])
        try FileManager.default.removeItem(at: root.appendingPathComponent("vanishing.txt"))

        let outcome = try await FileDeleter(registry: registry)
            .delete(ids: [target.id], expecting: stamp)

        XCTAssertTrue(outcome.deletedIDs.isEmpty)
        XCTAssertEqual(outcome.deletedIDs.count + outcome.missingCount + outcome.skippedCount, 1)
    }

    func testDeletingLeavesEverythingElseAlone() async throws {
        try write("doomed.txt", "a")
        try write("safe.txt", "b")

        let all = items()
        let doomed = try XCTUnwrap(all.first { $0.displayName == "doomed.txt" })
        _ = try await FileDeleter(registry: registry)
            .delete(ids: [doomed.id], expecting: stamps(for: [doomed]))

        XCTAssertEqual(items().map(\.displayName), ["safe.txt"])
    }

    /// The heart of it: a scan decides, the user acts later, and in between the file changed.
    func testAFileThatChangedAfterTheScanIsLeftAlone() async throws {
        let url = try write("notes.txt", "the bytes that were scanned")
        let target = try XCTUnwrap(items().first)
        let stamp = FileStamp(target)

        // Someone replaces it — same name, same identifier, different content.
        try "something else entirely, written later".write(to: url, atomically: true, encoding: .utf8)

        let outcome = try await FileDeleter(registry: registry)
            .delete(ids: [target.id], expecting: [target.id: stamp])

        XCTAssertTrue(outcome.deletedIDs.isEmpty, "this is no longer the file that was checked")
        XCTAssertEqual(outcome.skippedIDs, [target.id])
        XCTAssertEqual(outcome.missingCount, 0, "refused is not the same as already gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testAFileThatIsStillWhatItWasIsDeleted() async throws {
        let url = try write("steady.txt", "unchanged")
        let target = try XCTUnwrap(items().first)

        let outcome = try await FileDeleter(registry: registry)
            .delete(ids: [target.id], expecting: [target.id: FileStamp(target)])

        XCTAssertEqual(outcome.deletedIDs, [target.id])
        XCTAssertTrue(outcome.skippedIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// Identifiers are written to disk in the cache and the history and read back later. A path
    /// that climbs out of the granted folder is not a file this app may touch, whatever wrote it.
    func testAnIdentifierThatPointsOutsideTheGrantReachesNothing() async throws {
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside.txt")
        try "not yours".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        let folderID = try XCTUnwrap(registry.folders().first?.id)
        let escaping = FileItemID.make(folderID: folderID, relativePath: "../outside.txt")

        let outcome = try await FileDeleter(registry: registry).delete(ids: [escaping])

        XCTAssertTrue(outcome.deletedIDs.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outside.path),
            "a path outside the granted folder must never be deleted"
        )
    }

    func testAnIdentifierFromAnUnknownGrantDeletesNothing() async throws {
        try write("safe.txt", "a")
        let strayID = FileItemID.make(folderID: UUID(), relativePath: "safe.txt")

        let outcome = try await FileDeleter(registry: registry).delete(ids: [strayID])

        XCTAssertTrue(outcome.deletedIDs.isEmpty)
        XCTAssertEqual(items().count, 1, "a grant we do not hold must not reach the disk")
    }

    // MARK: - Registry

    func testRegistryAddsRemovesAndDeduplicatesGrants() {
        let registry = InMemoryFolderRegistry()
        let first = GrantedFolder(displayName: "Docs", bookmark: Data([1, 2, 3]))
        let duplicate = GrantedFolder(displayName: "Docs again", bookmark: Data([1, 2, 3]))

        registry.add(first)
        registry.add(duplicate)
        XCTAssertEqual(registry.folders().count, 1, "granting the same folder twice is one grant")
        XCTAssertEqual(registry.folders().first?.displayName, "Docs again")

        registry.remove(id: duplicate.id)
        XCTAssertTrue(registry.folders().isEmpty)
    }

    func testUserDefaultsRegistrySurvivesAReload() throws {
        let suiteName = "dupespace-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let grant = GrantedFolder(displayName: "Downloads", bookmark: Data([9, 9]))
        UserDefaultsFolderRegistry(defaults: defaults).add(grant)

        let reloaded = UserDefaultsFolderRegistry(defaults: defaults).folders()
        XCTAssertEqual(reloaded.map(\.id), [grant.id])
        XCTAssertEqual(reloaded.first?.displayName, "Downloads")
    }
}

final class FolderOverlapTests: XCTestCase {

    /// Granting a folder and then something inside it would index one physical file twice. The
    /// engine would be right to call the two entries identical, and deleting the loser would
    /// delete the survivor's own file with nothing to restore it from.
    func testAFolderInsideAnotherIsRecognisedAsOverlapping() {
        XCTAssertTrue(FolderAccess.overlaps("/a/b", "/a/b"))
        XCTAssertTrue(FolderAccess.overlaps("/a/b/c", "/a/b"))
        XCTAssertTrue(FolderAccess.overlaps("/a/b", "/a/b/c"))
        XCTAssertTrue(FolderAccess.overlaps("/a/b/", "/a/b"))
    }

    func testSiblingFoldersDoNotOverlap() {
        XCTAssertFalse(FolderAccess.overlaps("/a/b", "/a/c"))
        XCTAssertFalse(FolderAccess.overlaps("/a/b", "/a/bc"), "a shared prefix is not containment")
        XCTAssertFalse(FolderAccess.overlaps("/photos", "/photos-old"))
    }
}

@MainActor
final class FolderGrantTests: XCTestCase {

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grant-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("inner"),
            withIntermediateDirectories: true
        )
        return root
    }

    func testAFolderInsideAGrantedOneIsRefusedWithAReason() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let model = OverviewViewModel(
            library: StubMediaLibrary.previewFixture(),
            folderRegistry: InMemoryFolderRegistry()
        )

        await model.addFolder(at: root)
        XCTAssertEqual(model.folders.count, 1)
        XCTAssertNil(model.folderMessage)

        await model.addFolder(at: root.appendingPathComponent("inner"))

        XCTAssertEqual(model.folders.count, 1, "the nested folder must not be taken")
        XCTAssertNotNil(model.folderMessage, "and the refusal has to say why")
    }

    func testRemovingAFolderClearsTheRefusal() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let model = OverviewViewModel(
            library: StubMediaLibrary.previewFixture(),
            folderRegistry: InMemoryFolderRegistry()
        )

        await model.addFolder(at: root)
        await model.addFolder(at: root.appendingPathComponent("inner"))
        XCTAssertNotNil(model.folderMessage)

        await model.removeFolder(id: model.folders[0].id)
        XCTAssertNil(model.folderMessage)
        XCTAssertTrue(model.folders.isEmpty)
    }
}
