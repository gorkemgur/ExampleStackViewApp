import XCTest
import DupeCore
@testable import DupeSpace

/// The type every honest reading on the deletion screen is derived from.
final class DeletionProgressTests: XCTestCase {

    func testAFractionOfNothingIsZeroRatherThanNotANumber() {
        let progress = DeletionProgress(stage: .files, settled: 0, total: 0, isDeterminate: false)

        XCTAssertEqual(progress.fraction, 0)
    }

    func testTheFractionIsClampedAtBothEnds() {
        XCTAssertEqual(
            DeletionProgress(stage: .files, settled: 99, total: 10, isDeterminate: true).fraction,
            1
        )
        XCTAssertEqual(
            DeletionProgress(stage: .files, settled: -4, total: 10, isDeterminate: true).fraction,
            0
        )
    }

    func testAStartingReportHasSettledNothing() {
        let progress = DeletionProgress.starting(total: 12, isDeterminate: true, stage: .files)

        XCTAssertEqual(progress.settled, 0)
        XCTAssertEqual(progress.total, 12)
        XCTAssertTrue(progress.isDeterminate)
        XCTAssertEqual(progress.stage, .files)
    }
}

/// The words the accessibility identifiers are built from.
///
/// These read like trivia and are not: `review.section.image.0` is a contract between the app
/// and both the UI tests and the simulator walk, and it is assembled from `slug`. Deriving it
/// from `MediaKind.rawValue` — an `Int` enum — meant inserting a case silently rebound every
/// identifier downstream of it.
final class KindCopyTests: XCTestCase {

    func testEveryKindHasItsOwnWord() {
        let slugs = MediaKind.allCases.map(KindCopy.slug(for:))

        XCTAssertEqual(slugs, ["image", "video", "document"])
        XCTAssertEqual(Set(slugs).count, MediaKind.allCases.count)
    }

    func testNoKindAtAllIsEverything() {
        XCTAssertEqual(KindCopy.slug(for: nil), "all")
        XCTAssertEqual(KindCopy.title(for: nil), "Everything")
    }

    /// A slug that is not URL- and identifier-safe would break the contract in a way nothing
    /// else here would catch.
    func testSlugsAreSafeToPutInAnIdentifier() {
        for kind in MediaKind.allCases {
            let slug = KindCopy.slug(for: kind)
            XCTAssertFalse(slug.isEmpty)
            XCTAssertTrue(slug.allSatisfy { $0.isLowercase && $0.isLetter })
        }
    }

    func testEveryKindHasAGlyphAndAName() {
        for kind in MediaKind.allCases {
            XCTAssertFalse(KindCopy.title(for: kind).isEmpty)
            XCTAssertFalse(KindCopy.symbolName(for: kind).isEmpty)
        }
    }
}
