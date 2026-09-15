import XCTest
@testable import DupeSpace
import DupeCore

/// The fixtures, judged by the engine the app actually runs.
///
/// The stub analyzer now hands out feature prints as well as hashes, because the matcher prefers
/// prints and a fixture without them would route every UI test down the fallback — the branch a
/// phone never takes. These tests pin that the prints are wired all the way through, and that at
/// least one pair in the fixture exists *only* because of them.
final class FeaturePrintFixtureTests: XCTestCase {

    private func groups(of analyzer: StubAssetAnalyzer, items: [MediaItem]) async throws -> [DuplicateGroup] {
        try await ScanPipeline(analyzer: analyzer).run(items: items).groups
    }

    private func isPaired(_ groups: [DuplicateGroup], _ a: String, _ b: String) -> Bool {
        groups.contains { $0.itemIDs.contains(a) && $0.itemIDs.contains(b) }
    }

    private var croppedPair: (String, String) {
        let index = StubAssetAnalyzer.croppedPairIndex
        return ("crowd-\(index)-a", "crowd-\(index)-b")
    }

    func testTheCroppedPairIsFoundOnlyBecauseOfItsFeaturePrint() async throws {
        let found = try await groups(
            of: .crowdedFixture(),
            items: StubMediaLibrary.sampleItems() + StubMediaLibrary.crowdItems()
        )

        XCTAssertTrue(
            isPaired(found, croppedPair.0, croppedPair.1),
            "34 of 64 bits apart: on hashes alone this pair is indistinguishable from two unrelated photographs"
        )
    }

    /// The same fixture with the prints taken away. This is the measurement from
    /// `docs/OPPORTUNITIES.md` §9.1 expressed as a test: eleven pairs survive on their hashes
    /// and the cropped one does not, so the pair above is proof the print did the work rather
    /// than proof the fixture is generous.
    func testWithoutItsPrintTheCroppedPairIsInvisibleAndTheOthersAreNot() async throws {
        let crowded = StubAssetAnalyzer.crowdedFixture()
        let blinded = StubAssetAnalyzer(
            digests: crowded.digests,
            hashes: crowded.hashes,
            prints: [:],
            signatures: crowded.signatures
        )

        let found = try await groups(
            of: blinded,
            items: StubMediaLibrary.sampleItems() + StubMediaLibrary.crowdItems()
        )

        XCTAssertFalse(isPaired(found, croppedPair.0, croppedPair.1), "the hashes cannot see a crop")
        XCTAssertTrue(isPaired(found, "crowd-0-a", "crowd-0-b"), "seven bits apart is well within reach of the hashes")
    }

    func testEveryPairTheHashesUsedToFindIsStillFoundWithPrintsInPlay() async throws {
        let found = try await groups(
            of: .crowdedFixture(),
            items: StubMediaLibrary.sampleItems() + StubMediaLibrary.crowdItems()
        )

        for index in 0..<12 {
            XCTAssertTrue(
                isPaired(found, "crowd-\(index)-a", "crowd-\(index)-b"),
                "pair \(index) went missing when the matcher started preferring prints"
            )
        }
    }

    func testTheTidyLibraryStaysTidyUnderThePrintToo() async throws {
        let found = try await groups(of: .cleanFixture(), items: StubMediaLibrary.sampleItems())

        XCTAssertTrue(found.isEmpty, "a library with nothing duplicated in it must still find nothing")
    }

    /// The print must not reshape what the hashes already agreed about.
    ///
    /// Measured rather than assumed, and the measurement corrected the test: the burst arrives
    /// as three pairs, not one group of six. The frames sit in a chain — each a tenth from the
    /// next and four tenths from the one after — and `DuplicateClusterer` groups a seed with its
    /// own neighbours rather than taking a transitive closure, so a chain comes out in pieces.
    /// That is the behaviour with hashes and it is the behaviour with prints; this test exists
    /// to keep the two answers the same, whatever that answer is.
    func testThePrintReproducesTheBurstTheHashesFoundRatherThanReshapingIt() async throws {
        let fixture = StubAssetAnalyzer.uiTestFixture()
        let blinded = StubAssetAnalyzer(
            digests: fixture.digests,
            hashes: fixture.hashes,
            prints: [:],
            signatures: fixture.signatures
        )

        let shape = { (found: [DuplicateGroup]) in
            found
                .map { $0.itemIDs.sorted() }
                .filter { $0.contains { $0.hasPrefix("burst-") } }
                .sorted { ($0.first ?? "") < ($1.first ?? "") }
        }

        let withPrints = shape(try await groups(of: fixture, items: StubMediaLibrary.sampleItems()))
        let withHashes = shape(try await groups(of: blinded, items: StubMediaLibrary.sampleItems()))

        XCTAssertEqual(withPrints, [["burst-0", "burst-1"], ["burst-2", "burst-3"], ["burst-4", "burst-5"]])
        XCTAssertEqual(withPrints, withHashes, "the fixture's two descriptions of one burst have to agree")
    }
}
