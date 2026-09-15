import XCTest
import DupeCore
@testable import DupeSpace

/// An asset whose only interesting property is whether the library will part with it.
private struct FakeAsset: DeletableAsset {
    let localIdentifier: String
    let mayBeDeleted: Bool
}

/// What happens to an asset the photo library will not let this app delete.
///
/// `PHPhotoLibrary.performChanges` is atomic. One asset that cannot be removed — synced from a
/// computer, or living in somebody else's shared album — fails the entire request, so a person
/// who ticked two hundred photographs gets none of them and an error naming none of the causes.
/// The fix is to separate those before the request is made, which means the separation is a
/// decision, and a decision is a thing that can be tested.
final class DeletionRefusalTests: XCTestCase {

    // MARK: - Which assets are even sent

    func testAnAssetTheLibraryWillNotDeleteIsNeverSent() {
        let plan = DeletionTriage.plan([
            FakeAsset(localIdentifier: "mine", mayBeDeleted: true),
            FakeAsset(localIdentifier: "synced-from-a-mac", mayBeDeleted: false)
        ])

        XCTAssertEqual(plan.deletable, ["mine"])
        XCTAssertEqual(plan.refused, ["synced-from-a-mac"], "not sent, and not silently forgotten either")
    }

    func testOneRefusalDoesNotSinkTheRestOfTheBatch() {
        let plan = DeletionTriage.plan([
            FakeAsset(localIdentifier: "a", mayBeDeleted: true),
            FakeAsset(localIdentifier: "b", mayBeDeleted: true),
            FakeAsset(localIdentifier: "shared-album", mayBeDeleted: false),
            FakeAsset(localIdentifier: "d", mayBeDeleted: true)
        ])

        XCTAssertEqual(plan.deletable, ["a", "b", "d"], "the other three are the whole point")
        XCTAssertEqual(plan.refused, ["shared-album"])
    }

    func testABatchThatIsRefusedEntirelyAsksForNothing() {
        let plan = DeletionTriage.plan([
            FakeAsset(localIdentifier: "one", mayBeDeleted: false),
            FakeAsset(localIdentifier: "two", mayBeDeleted: false)
        ])

        XCTAssertTrue(
            plan.deletable.isEmpty,
            "an empty change request still raises the system confirmation, for a deletion that cannot happen"
        )
        XCTAssertEqual(plan.refused, ["one", "two"])
    }

    // MARK: - What the outcome says about it

    func testARefusalIsNotCountedAsAlreadyGone() {
        let outcome = DeletionOutcome(
            requestedIDs: ["kept", "refused"],
            deletedIDs: ["kept"],
            refusedIDs: ["refused"]
        )

        XCTAssertEqual(outcome.refusedCount, 1)
        XCTAssertEqual(
            outcome.missingCount,
            0,
            "'already gone' is what is left over after every other explanation; a refusal is an explanation"
        )
    }

    func testARefusedAssetIsNeverReportedAsDeleted() {
        let outcome = DeletionOutcome(
            requestedIDs: ["a", "b"],
            deletedIDs: ["a"],
            refusedIDs: ["b"]
        )

        XCTAssertFalse(
            outcome.deletedIDs.contains("b"),
            "the review list drops whatever this names, and an asset still in the library must not be dropped"
        )
    }

    // MARK: - Through the composite, which is what the screen actually talks to

    func testARefusalFromThePhotoHalfReachesTheCaller() async throws {
        let photos = StubDeleter(behaviour: .refuse(["photo-b"]))
        let files = StubDeleter()

        let outcome = try await CompositeDeleter(photos: photos, files: files)
            .delete(ids: ["photo-a", "photo-b"], expecting: [:])

        XCTAssertEqual(outcome.deletedIDs, ["photo-a"])
        XCTAssertEqual(
            outcome.refusedIDs,
            ["photo-b"],
            "the composite read only deletedIDs off the photo half, so every refusal it made was thrown away between the deleter and the screen"
        )
    }

    func testASkipFromThePhotoHalfAlsoSurvivesTheComposite() async throws {
        let photos = StubRefusingDeleter(skipping: ["photo-b"])
        let files = StubDeleter()

        let outcome = try await CompositeDeleter(photos: photos, files: files)
            .delete(ids: ["photo-a", "photo-b"], expecting: [:])

        XCTAssertEqual(outcome.deletedIDs, ["photo-a"])
        XCTAssertEqual(outcome.skippedIDs, ["photo-b"])
    }
}

/// Reports a skip rather than a refusal, so the two channels can be told apart at the seam.
private final class StubRefusingDeleter: MediaDeleting, @unchecked Sendable {
    private let skipped: [String]
    init(skipping: [String]) { self.skipped = skipping }

    func delete(ids: [String], expecting _: [String: FileStamp]) async throws -> DeletionOutcome {
        let set = Set(skipped)
        return DeletionOutcome(
            requestedIDs: ids,
            deletedIDs: ids.filter { !set.contains($0) },
            skippedIDs: ids.filter { set.contains($0) }
        )
    }
}
