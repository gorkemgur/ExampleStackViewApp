import XCTest
@testable import DupeSpace

/// Can a file be deleted reversibly on iOS? In the app's own sandbox: no.
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
/// THE ANSWER, MEASURED. `trashItem` refuses, with `NSCocoaErrorDomain` 3328:
///
///     "Trashing is not supported since this is a non-public location"
///
/// Both for the temporary directory and for Documents. So iOS has no trash inside an app's
/// container, the four screens that say folder deletion is immediate are right, and the design
/// I was about to build on this does not exist. Keeping the tests as an assertion of the
/// refusal rather than deleting them: the next person to have this idea — me, in a month —
/// gets the error code instead of the afternoon.
///
/// WHAT IS STILL OPEN, and these tests say nothing about it: the folders this app actually
/// deletes from are not in its container. They are picked through the Files app and served by
/// a provider — iCloud Drive, On My iPhone, somebody else's — which is a *public* location, and
/// "non-public location" is precisely the reason given for the refusal here. Whether a provider
/// grants a trash can only be found out against a real folder grant, which needs a device.
/// Until then the app's copy stays as it is, because it is right about everything that has been
/// measured.
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

    /// `NSFeatureUnsupportedError`. Asserted by code, so a future iOS that starts allowing this
    /// turns the test red and sends somebody back to read the rest of this file.
    private let featureUnsupported = 3328

    /// The app's own temporary directory: refused.
    func testTrashingIsRefusedInsideTheAppsOwnContainer() throws {
        let url = try file(named: "keep-me.txt", in: root)

        var landed: NSURL?
        XCTAssertThrowsError(
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed),
            "iOS now allows trashing inside the container — the folder half can offer a "
            + "Recently Deleted after all, and four screens need their copy changed"
        ) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSCocoaErrorDomain)
            XCTAssertEqual(
                nsError.code, featureUnsupported,
                "refused for a different reason than 'not supported here': \(nsError)"
            )
        }

        // And nothing was half-done: a refusal must leave the file exactly where it was.
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "the call refused and the file is gone anyway, which is the worst of both"
        )
    }

    /// Documents, which is what a user-visible folder in "On My iPhone" is when the app owns
    /// it: refused as well, and with the reason spelled out — "non-public location".
    func testTrashingIsRefusedInDocumentsToo() throws {
        let documents = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )
        let directory = documents.appendingPathComponent("trash-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try file(named: "keep-me.txt", in: directory)
        var landed: NSURL?
        XCTAssertThrowsError(
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
        ) { error in
            XCTAssertEqual((error as NSError).code, featureUnsupported)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// Belt and braces on the refusal above: whatever iOS decides about trashing, a call
    /// against something that was never there has to fail rather than report success — a
    /// deleter that believed it would report a file as recoverable when it is not.
    func testTrashingSomethingThatIsNotThereFails() {
        let missing = root.appendingPathComponent("never-existed.txt")
        XCTAssertThrowsError(try FileManager.default.trashItem(at: missing, resultingItemURL: nil))
    }
}
