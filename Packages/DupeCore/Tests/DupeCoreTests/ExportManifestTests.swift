import XCTest
@testable import DupeCore

final class ExportManifestTests: XCTestCase {

    private func item(_ id: String, name: String, bytes: Int64 = 100, kind: MediaKind = .image) -> MediaItem {
        MediaItem(id: id, source: .photoLibrary, kind: kind, displayName: name, byteSize: bytes)
    }

    private func candidate(_ id: String, keeper: String, group: String = "g1", tier: RegretTier = .identical) -> DeletionCandidate {
        DeletionCandidate(
            id: id,
            groupID: group,
            keeperID: keeper,
            tier: tier,
            bytes: 100,
            isPreSelected: true
        )
    }

    /// The failure mode that would make this feature worse than not having it: two copies in a
    /// group almost always share a display name — that is usually why they matched — so writing
    /// them out under it means the second lands on top of the first and the export silently
    /// holds half of what its manifest claims.
    func testCopiesSharingANameGetDistinctFiles() {
        let items = [
            "a": item("a", name: "IMG_4021.MOV", kind: .video),
            "b": item("b", name: "IMG_4021.MOV", kind: .video),
            "keeper": item("keeper", name: "IMG_4021.MOV", kind: .video)
        ]
        let plan = ExportManifestBuilder.entries(
            for: [candidate("a", keeper: "keeper"), candidate("b", keeper: "keeper")],
            items: items
        )

        XCTAssertEqual(plan.count, 2)
        let names = plan.map(\.entry.exportedFileName)
        XCTAssertEqual(Set(names).count, 2, "two originals may never be written to one filename")
        XCTAssertTrue(names.allSatisfy { $0.hasSuffix(".MOV") }, "the extension has to survive")
    }

    func testAFilenameCannotEscapeTheExportFolder() {
        let name = ExportManifestBuilder.fileName(
            for: item("a", name: "../../etc/passwd"),
            index: 1
        )

        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.hasPrefix("."))
    }

    func testAnItemWithNoNameStillGetsOne() {
        let name = ExportManifestBuilder.fileName(for: item("a", name: ""), index: 7)

        XCTAssertFalse(name.isEmpty)
        XCTAssertTrue(name.hasPrefix("007-"))
    }

    /// The manifest's whole purpose: it is the only record of which copy stayed, and that is
    /// what makes a wrong decision recoverable rather than merely visible.
    func testEveryRowNamesTheCopyThatStays() {
        let items = [
            "a": item("a", name: "one.jpg"),
            "keeper": item("keeper", name: "the-good-one.jpg")
        ]
        let plan = ExportManifestBuilder.entries(
            for: [candidate("a", keeper: "keeper", tier: .similar)],
            items: items
        )

        XCTAssertEqual(plan.first?.entry.keptItemID, "keeper")
        XCTAssertEqual(plan.first?.entry.keptDisplayName, "the-good-one.jpg")
        XCTAssertEqual(plan.first?.entry.cost, "similar shot")
    }

    func testTheManifestSurvivesARoundTrip() throws {
        let items = ["a": item("a", name: "one.jpg"), "keeper": item("keeper", name: "two.jpg")]
        let entries = ExportManifestBuilder.entries(for: [candidate("a", keeper: "keeper")], items: items)
            .map(\.entry)
        let manifest = ExportManifest(createdAt: Date(timeIntervalSince1970: 1_750_000_000), entries: entries)

        let decoded = try ExportManifest.decoded(from: manifest.encoded())

        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.totalBytes, 100)
    }

    /// A manifest is a document someone opens in five years, in a text editor, on a machine
    /// that has never heard of this app. `"kind": 1` is not a receipt.
    func testTheManifestIsReadableByAPerson() throws {
        let items = ["a": item("a", name: "one.mov", kind: .video), "keeper": item("keeper", name: "two.mov", kind: .video)]
        let entries = ExportManifestBuilder.entries(for: [candidate("a", keeper: "keeper")], items: items)
            .map(\.entry)
        let text = try XCTUnwrap(String(data: ExportManifest(createdAt: Date(), entries: entries).encoded(), encoding: .utf8))

        XCTAssertTrue(text.contains("\"kind\" : \"video\""), "the kind has to be a word, not an enum's Int")
        XCTAssertTrue(text.contains("\"keptDisplayName\" : \"two.mov\""))
    }

    /// A candidate whose item is not in the scan's table cannot be exported, and a row in the
    /// manifest with no file beside it is exactly the lie this document must not tell.
    func testACandidateWithNoItemIsDropped() {
        let plan = ExportManifestBuilder.entries(
            for: [candidate("ghost", keeper: "keeper")],
            items: ["keeper": item("keeper", name: "two.jpg")]
        )

        XCTAssertTrue(plan.isEmpty)
    }
}
