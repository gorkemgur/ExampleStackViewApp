import XCTest
@testable import DupeCore

final class NameHeuristicTests: XCTestCase {

    func testStripsNumberedDuplicateSuffix() {
        XCTAssertEqual(NameHeuristic.canonicalName("report (1).pdf"), "report.pdf")
        XCTAssertEqual(NameHeuristic.canonicalName("report (12).pdf"), "report.pdf")
        XCTAssertEqual(NameHeuristic.canonicalName("report (1) (2).pdf"), "report.pdf")
    }

    func testStripsCopyWording() {
        XCTAssertEqual(NameHeuristic.canonicalName("report copy.pdf"), "report.pdf")
        XCTAssertEqual(NameHeuristic.canonicalName("report Copy 3.pdf"), "report.pdf")
        XCTAssertEqual(NameHeuristic.canonicalName("report - copy.pdf"), "report.pdf")
    }

    func testIsCaseAndExtensionInsensitive() {
        XCTAssertEqual(NameHeuristic.canonicalName("Report.PDF"), "report.pdf")
        XCTAssertEqual(
            NameHeuristic.canonicalName("Report (1).PDF"),
            NameHeuristic.canonicalName("report.pdf")
        )
    }

    /// The failure that would matter: cameras name files with trailing numbers, and reducing
    /// those to a common stem would cluster photos that have nothing to do with each other.
    func testDoesNotStripTrailingNumbersThatAreJustPartOfTheName() {
        XCTAssertEqual(NameHeuristic.canonicalName("IMG-1234.HEIC"), "img-1234.heic")
        XCTAssertEqual(NameHeuristic.canonicalName("IMG_5678.HEIC"), "img_5678.heic")
        XCTAssertNotEqual(
            NameHeuristic.canonicalName("IMG-1234.HEIC"),
            NameHeuristic.canonicalName("IMG-5678.HEIC")
        )
    }

    func testLeavesOrdinaryNamesAlone() {
        XCTAssertEqual(NameHeuristic.canonicalName("holiday.pdf"), "holiday.pdf")
        XCTAssertEqual(NameHeuristic.canonicalName("no extension"), "no extension")
        XCTAssertEqual(NameHeuristic.canonicalName(""), "")
    }

    func testLooksLikeCopy() {
        XCTAssertTrue(NameHeuristic.looksLikeCopy("report (1).pdf"))
        XCTAssertTrue(NameHeuristic.looksLikeCopy("report copy.pdf"))
        XCTAssertFalse(NameHeuristic.looksLikeCopy("report.pdf"))
        XCTAssertFalse(NameHeuristic.looksLikeCopy("IMG_0001.HEIC"))
    }

    func testClustersNamesThatReduceTogether() {
        let items = [
            Fixtures.item("a", kind: .document), Fixtures.item("b", kind: .document),
            Fixtures.item("c", kind: .document)
        ].enumerated().map { index, item -> MediaItem in
            var copy = item
            copy.displayName = ["report.pdf", "report (1).pdf", "invoice.pdf"][index]
            return copy
        }

        let clusters = NameHeuristic.clusters(for: items)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].canonicalName, "report.pdf")
        XCTAssertEqual(clusters[0].itemIDs, ["a", "b"])
    }

    func testItemsAlreadyExplainedByContentAreLeftOut() {
        var first = Fixtures.item("a", kind: .document)
        first.displayName = "report.pdf"
        var second = Fixtures.item("b", kind: .document)
        second.displayName = "report (1).pdf"

        XCTAssertTrue(NameHeuristic.clusters(for: [first, second], excluding: ["a"]).isEmpty)
    }

    func testItemsWithoutNamesAreIgnored() {
        var blank = Fixtures.item("a", kind: .document)
        blank.displayName = "   "
        var other = Fixtures.item("b", kind: .document)
        other.displayName = ""
        XCTAssertTrue(NameHeuristic.clusters(for: [blank, other]).isEmpty)
    }
}
