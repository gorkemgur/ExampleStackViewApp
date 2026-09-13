import XCTest
@testable import DupeCore

/// The same picture in the photo library and in a folder the user handed over.
///
/// This is the claim the app can make that nothing else on the phone can. Apple's Duplicates
/// looks inside the photo library and stops at its edge. A file browser looks at files and
/// cannot see inside the library at all. So the copy you exported to Files — or saved out of a
/// chat, or pulled off a camera into a folder — is invisible to both, and it is the duplicate
/// people are most certain they do not have.
///
/// It was invisible to this app as well, for a quieter reason: `edges(hashes:)` compares every
/// fingerprint against every other in one sweep, and the two analyzers were reducing pictures
/// with two different downsamplers at two different sizes. The same photograph indexed both
/// ways did not necessarily land on the same fingerprint. That is fixed in the analyzers, and
/// tested there; these are the tests for the part that has to *say so*.
final class CrossSourceTests: XCTestCase {

    private func group(_ items: [MediaItem]) -> ReviewGroup {
        ReviewGroup(
            id: "g",
            tier: .identical,
            keeper: items[0],
            candidates: items.dropFirst().map {
                DeletionCandidate(
                    id: $0.id,
                    groupID: "g",
                    keeperID: items[0].id,
                    tier: .identical,
                    bytes: $0.byteSize,
                    isPreSelected: true
                )
            },
            items: items
        )
    }

    func testAGroupHoldingBothIsMarkedAsSuch() {
        let crossing = group([
            Fixtures.item("in-the-library", source: .photoLibrary),
            Fixtures.item("in-a-folder", source: .fileFolder)
        ])
        XCTAssertTrue(crossing.spansLibraryAndFolders)
    }

    /// The half that stops the sentence appearing on every screen. A claim that is printed
    /// whether or not it is true is not a claim, it is decoration — and this one is the app's
    /// single most distinctive thing to say, so it has to be earned every time it is said.
    func testAGroupEntirelyInsideTheLibraryIsNot() {
        let inside = group([
            Fixtures.item("one", source: .photoLibrary),
            Fixtures.item("two", source: .photoLibrary),
            Fixtures.item("three", source: .photoLibrary)
        ])
        XCTAssertFalse(inside.spansLibraryAndFolders)
    }

    func testAGroupEntirelyInFoldersIsNotEither() {
        let outside = group([
            Fixtures.item("one", source: .fileFolder),
            Fixtures.item("two", source: .fileFolder)
        ])
        XCTAssertFalse(outside.spansLibraryAndFolders)
    }

    /// Three copies, and only one of them on the other side of the line — which is the shape
    /// this actually takes in a real library, where a picture has two copies in the camera roll
    /// and a third that was exported once.
    func testOneFolderCopyAmongLibraryOnesIsEnough() {
        let mixed = group([
            Fixtures.item("one", source: .photoLibrary),
            Fixtures.item("two", source: .photoLibrary),
            Fixtures.item("exported-once", source: .fileFolder)
        ])
        XCTAssertTrue(mixed.spansLibraryAndFolders)
    }
}
