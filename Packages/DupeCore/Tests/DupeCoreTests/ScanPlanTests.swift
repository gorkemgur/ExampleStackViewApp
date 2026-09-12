import XCTest
@testable import DupeCore

/// The plan is a promise made to someone before their library is opened, so the tests that
/// matter are the ones that catch it promising less work than the pipeline will actually do.
final class ScanPlanTests: XCTestCase {

    private func video(_ id: String, duration: Double, width: Int = 1920, height: Int = 1080, local: Bool = true) -> MediaItem {
        MediaItem(
            id: id,
            source: .photoLibrary,
            kind: .video,
            displayName: id,
            byteSize: Int64(duration * 1_000_000),
            pixelWidth: width,
            pixelHeight: height,
            duration: duration,
            isLocallyAvailable: local
        )
    }

    func testEveryLocalPhotoIsCountedAsRead() {
        // Three photographs with nothing in common but being photographs: no shared byte size,
        // no shared pixel size, so metadata alone settles nothing and all three are opened.
        let items = [
            Fixtures.item("a", bytes: 1_000_000, width: 4032, height: 3024),
            Fixtures.item("b", bytes: 2_000_000, width: 3000, height: 2000),
            Fixtures.item("c", bytes: 3_000_000, width: 1200, height: 1600),
        ]

        let plan = ScanPlan.of(items)

        XCTAssertEqual(plan.indexed, 3)
        XCTAssertEqual(plan.read, 3, "every local image is fingerprinted — the plan must say so")
        XCTAssertEqual(plan.untouched, 0)
    }

    func testCloudOnlyOriginalsAreNeverRead() {
        let items = [
            Fixtures.item("here", bytes: 1_000_000),
            Fixtures.item("cloud", bytes: 2_000_000, local: false),
        ]

        let plan = ScanPlan.of(items)

        XCTAssertEqual(plan.indexed, 2)
        XCTAssertEqual(plan.cloudOnly, 1)
        XCTAssertEqual(plan.read, 1, "reading a cloud-only original would mean downloading it")
        XCTAssertEqual(plan.untouched, 1)
    }

    func testAVideoWithNoPlausiblePartnerIsNeverOpened() {
        let items = [video("short", duration: 4), video("long", duration: 90)]

        let plan = ScanPlan.of(items)

        XCTAssertEqual(plan.read, 0, "no two videos are close enough in length to be worth a decode")
        XCTAssertEqual(plan.untouched, 2)
    }

    func testVideosOfTheSameLengthAreBothOpened() {
        let items = [video("a", duration: 30), video("b", duration: 30.2)]

        let plan = ScanPlan.of(items)

        XCTAssertEqual(plan.read, 2)
    }

    /// The one that stops the plan drifting away from the pipeline.
    ///
    /// The plan's whole value is that it is checkable against what happens next, so it is
    /// checked: everything the pipeline actually opens — digested, fingerprinted or sampled —
    /// has to be something the plan said would be opened. A stage that reads anything
    /// unannounced fails here rather than in front of someone who was told it would not.
    func testThePipelineNeverOpensAnythingThePlanDidNotPromise() async throws {
        let items = [
            Fixtures.item("photo-twin-a", bytes: 1_000_000, width: 4032, height: 3024),
            Fixtures.item("photo-twin-b", bytes: 1_000_000, width: 4032, height: 3024),
            Fixtures.item("photo-lonely", bytes: 5_000_000, width: 3000, height: 2000),
            Fixtures.item("cloud", bytes: 9_000_000, local: false),
            video("clip-a", duration: 30),
            video("clip-b", duration: 30.2),
            video("clip-lonely", duration: 300),
            Fixtures.item("doc-twin-a", kind: .document, bytes: 4_096, width: 0, height: 0),
            Fixtures.item("doc-twin-b", kind: .document, bytes: 4_096, width: 0, height: 0),
            Fixtures.item("doc-lonely", kind: .document, bytes: 77, width: 0, height: 0),
        ]

        let plan = ScanPlan.of(items)
        let analyzer = RecordingAnalyzer()
        _ = try await ScanPipeline(analyzer: analyzer).run(items: items)

        let opened = analyzer.opened
        let promised = plan.promisedIDs

        XCTAssertFalse(opened.isEmpty, "the fixture must give the pipeline something to open")
        XCTAssertLessThanOrEqual(
            opened.count, plan.read,
            "the pipeline opened \(opened.count) items after the plan promised \(plan.read)"
        )
        XCTAssertTrue(
            opened.isSubset(of: promised),
            "opened something the plan said it would not touch: \(opened.subtracting(promised))"
        )
        XCTAssertFalse(opened.contains("cloud"), "a cloud-only original was opened")
        XCTAssertFalse(opened.contains("clip-lonely"), "a video with no partner by length was opened")
        XCTAssertFalse(opened.contains("doc-lonely"), "a document with a unique shape was opened")
        XCTAssertTrue(opened.contains("photo-lonely"), "every local photograph is fingerprinted")
    }

    func testLinesCoverOnlyTheKindsThatArePresent() {
        let items = [
            Fixtures.item("a", bytes: 1_000_000),
            video("v", duration: 10),
        ]

        let plan = ScanPlan.of(items)

        XCTAssertEqual(plan.lines.map(\.kind), [.image, .video])
        XCTAssertEqual(plan.lines.first?.indexed, 1)
    }

    func testBytesIncludeThePairedLivePhotoMovie() {
        let items = [Fixtures.item("live", bytes: 3_000_000, pairedVideoBytes: 1_500_000, live: true)]

        let plan = ScanPlan.of(items)

        XCTAssertEqual(plan.bytes, 4_500_000, "a Live Photo occupies its movie as well as its still")
    }

    func testFoldersAreCountedSeparatelyFromTheLibrary() {
        let items = [
            Fixtures.item("library", bytes: 1_000_000),
            Fixtures.item("folder", source: .fileFolder, kind: .document, bytes: 2_000_000, width: 0, height: 0),
        ]

        let plan = ScanPlan.of(items)

        XCTAssertEqual(plan.fromFolders, 1)
        XCTAssertEqual(plan.indexed, 2)
    }

    func testAnEmptyLibraryPlansNothing() {
        let plan = ScanPlan.of([])

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.lines.isEmpty)
        XCTAssertEqual(plan.read, 0)
        XCTAssertEqual(plan.bytes, 0)
    }
}

/// Records every read of every kind, which `StubAnalyzer` does not: it takes the protocol's
/// free `videoSignature`, so a video being opened leaves no trace there.
private final class RecordingAnalyzer: AssetAnalyzing, @unchecked Sendable {

    private let lock = NSLock()
    private var ids: Set<String> = []

    var opened: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return ids
    }

    private func record(_ id: String) {
        lock.lock(); ids.insert(id); lock.unlock()
    }

    func contentDigest(for item: MediaItem) async -> ContentDigestResult {
        record(item.id)
        return .unavailable
    }

    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
        record(item.id)
        return nil
    }

    func videoSignature(for item: MediaItem) async -> VideoSignature? {
        record(item.id)
        return nil
    }
}
