import XCTest
@testable import DupeSpace

/// Can a file be deleted reversibly on iOS, or only permanently?
///
/// The whole shape of the folder half rests on this one answer. `FileDeleter` calls
/// `removeItem`, which is immediate and final, and every screen in the app that mentions
/// folders says so: "deletion is immediate and there is no Recently Deleted to fall back on."
/// That sentence was written from the assumption that iOS has no trash for files, and the
/// assumption was never measured.
///
/// It is worth measuring because the photo half is not actually better than a trash — it *is* a
/// trash. `PhotoKitDeleter` moves assets to Recently Deleted and the space comes back in thirty
/// days or when the user empties the album, which the app says in four places. So if
/// `FileManager.trashItem` works here, the two halves can make the same promise instead of two
/// different ones, and the folder half keeps its delete key.
///
/// What this can and cannot settle: it tests files the app itself owns. A folder picked through
/// the Files app is served by a file provider — iCloud Drive, On My iPhone, or somebody else's
/// — and a provider is free to refuse. That refusal has to be handled where it happens; what
/// this fixes is the case of not even asking.
final class FileTrashTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func file(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("the bytes that must survive being deleted".utf8).write(to: url)
        return url
    }

    /// The question, asked plainly.
    func testAFileCanBeTrashedRatherThanErased() throws {
        let url = try file(named: "keep-me.txt", in: root)

        var landed: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
        } catch {
            XCTFail(
                "trashItem refused a file in the app's own temporary directory: \(error). "
                + "If this is how iOS behaves everywhere, the folder half cannot offer a "
                + "Recently Deleted and the copy that says so is right."
            )
            return
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "the file is still where it was, so nothing was trashed"
        )

        let resting = try XCTUnwrap(landed as URL?, "trashItem reported no resulting location")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resting.path),
            "trashItem named \(resting.path) but there is nothing there — that is erasure wearing a trash's name"
        )

        // The bytes, not just the entry: a trash that keeps an empty file is no trash.
        let recovered = try Data(contentsOf: resting)
        XCTAssertEqual(String(decoding: recovered, as: UTF8.self), "the bytes that must survive being deleted")

        // Informative rather than asserted: where it lands decides what the app can tell the
        // user about finding it again.
        print("trashItem put it at: \(resting.path)")
    }

    /// The same question for the Documents directory, which is what a user-visible folder in
    /// "On My iPhone" actually is when the app owns it.
    func testAFileInDocumentsCanBeTrashedToo() throws {
        let documents = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )
        let directory = documents.appendingPathComponent("trash-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try file(named: "keep-me.txt", in: directory)
        var landed: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
        } catch {
            XCTFail("trashItem refused a file in Documents: \(error)")
            return
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let resting = try XCTUnwrap(landed as URL?)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resting.path))
        print("from Documents, trashItem put it at: \(resting.path)")
    }

    /// A trash that silently succeeds on something that was never there would let the deleter
    /// report a file as recoverable when it is not.
    func testTrashingSomethingThatIsNotThereFails() {
        let missing = root.appendingPathComponent("never-existed.txt")
        XCTAssertThrowsError(try FileManager.default.trashItem(at: missing, resultingItemURL: nil))
    }
}
