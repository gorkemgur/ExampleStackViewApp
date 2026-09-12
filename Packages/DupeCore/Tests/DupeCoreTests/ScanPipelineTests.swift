import XCTest
@testable import DupeCore

/// Records what the pipeline asked for, so tests can assert on work *not* done — the cheap
/// stages exist precisely to keep expensive reads from happening.
final class StubAnalyzer: AssetAnalyzing, @unchecked Sendable {

    private let digests: [String: ContentDigestResult]
    private let hashes: [String: PerceptualHashes]
    private let delay: Duration

    private let lock = NSLock()
    private var _digestRequests: [String] = []
    private var _hashRequests: [String] = []

    init(
        digests: [String: ContentDigestResult] = [:],
        hashes: [String: PerceptualHashes] = [:],
        delay: Duration = .zero
    ) {
        self.digests = digests
        self.hashes = hashes
        self.delay = delay
    }

    var digestRequests: [String] {
        lock.lock(); defer { lock.unlock() }
        return _digestRequests
    }

    var hashRequests: [String] {
        lock.lock(); defer { lock.unlock() }
        return _hashRequests
    }

    func contentDigest(for item: MediaItem) async -> ContentDigestResult {
        if delay > .zero { try? await Task.sleep(for: delay) }
        lock.lock()
        _digestRequests.append(item.id)
        lock.unlock()
        return digests[item.id] ?? .unavailable
    }

    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
        if delay > .zero { try? await Task.sleep(for: delay) }
        lock.lock()
        _hashRequests.append(item.id)
        lock.unlock()
        return hashes[item.id]
    }
}

private func digest(_ seed: UInt8) -> ContentDigest {
    ContentDigest(bytes: [UInt8](repeating: seed, count: 32))
}

private func flipping(_ value: UInt64, bits: Int) -> UInt64 {
    var result = value
    for bit in 0..<bits { result ^= (UInt64(1) << UInt64(bit)) }
    return result
}

final class ScanPipelineTests: XCTestCase {

    private let baseD: UInt64 = 0x0F1E_2D3C_4B5A_6978
    private let baseP: UInt64 = 0xA1B2_C3D4_E5F6_0718

    // MARK: - Cheap stages

    func testMetadataSuspectsExcludeAnythingUniqueOnItsShape() {
        let items = [
            Fixtures.item("a", bytes: 100, width: 10, height: 10),
            Fixtures.item("b", bytes: 100, width: 10, height: 10),
            Fixtures.item("lonely", bytes: 999, width: 10, height: 10),
            Fixtures.item("other-shape", bytes: 100, width: 20, height: 10)
        ]
        XCTAssertEqual(ScanPipeline.metadataSuspects(items).map(\.id), ["a", "b"])
    }

    func testZeroByteItemsAreNeverSuspects() {
        let items = [
            Fixtures.item("a", bytes: 0, width: 10, height: 10),
            Fixtures.item("b", bytes: 0, width: 10, height: 10)
        ]
        XCTAssertTrue(ScanPipeline.metadataSuspects(items).isEmpty)
    }

    func testOnlySuspectsAreEverRead() async throws {
        let items = [
            Fixtures.item("a", bytes: 100, width: 10, height: 10),
            Fixtures.item("b", bytes: 100, width: 10, height: 10),
            Fixtures.item("unique", bytes: 7, width: 3, height: 3)
        ]
        let analyzer = StubAnalyzer(digests: ["a": .digest(digest(1)), "b": .digest(digest(1))])
        _ = try await ScanPipeline(analyzer: analyzer).run(items: items)

        XCTAssertEqual(analyzer.digestRequests.sorted(), ["a", "b"])
        XCTAssertFalse(analyzer.digestRequests.contains("unique"), "a unique shape must never be read")
    }

    // MARK: - Exact

    func testIdenticalDigestsFormAnExactGroup() async throws {
        let items = [
            Fixtures.item("keep", bytes: 100, width: 10, height: 10),
            Fixtures.item("copy", bytes: 100, width: 10, height: 10)
        ]
        let analyzer = StubAnalyzer(digests: ["keep": .digest(digest(9)), "copy": .digest(digest(9))])
        let result = try await ScanPipeline(analyzer: analyzer).run(items: items)

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].relation, .exact)
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates[0].tier, .identical)
        XCTAssertTrue(result.candidates[0].isPreSelected)
        XCTAssertEqual(result.reclaimableBytes, 100)
    }

    func testSameShapeDifferentBytesIsNotADuplicate() async throws {
        let items = [
            Fixtures.item("a", bytes: 100, width: 10, height: 10),
            Fixtures.item("b", bytes: 100, width: 10, height: 10)
        ]
        let analyzer = StubAnalyzer(digests: ["a": .digest(digest(1)), "b": .digest(digest(2))])
        let result = try await ScanPipeline(analyzer: analyzer).run(items: items)

        XCTAssertTrue(result.groups.isEmpty, "same size and dimensions is a coincidence, not proof")
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testCloudOnlyOriginalsAreReportedAndNeverGrouped() async throws {
        let items = [
            Fixtures.item("local", bytes: 100, width: 10, height: 10),
            Fixtures.item("cloud", bytes: 100, width: 10, height: 10)
        ]
        let analyzer = StubAnalyzer(digests: ["local": .digest(digest(3)), "cloud": .cloudOnly])
        let result = try await ScanPipeline(analyzer: analyzer).run(items: items)

        XCTAssertEqual(result.cloudOnlyIDs, ["cloud"])
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertFalse(analyzer.hashRequests.contains("cloud"), "a cloud-only item must not be downloaded to fingerprint it")
    }

    func testItemsAlreadyKnownToBeInTheCloudAreNeverTouched() async throws {
        let items = [
            Fixtures.item("local", bytes: 100, width: 10, height: 10),
            Fixtures.item("elsewhere", bytes: 100, width: 10, height: 10, local: false)
        ]
        let analyzer = StubAnalyzer(
            digests: ["local": .digest(digest(4)), "elsewhere": .digest(digest(4))],
            hashes: ["elsewhere": PerceptualHashes(dHash: 1, pHash: 1)]
        )
        let result = try await ScanPipeline(analyzer: analyzer).run(items: items)

        XCTAssertEqual(result.cloudOnlyIDs, ["elsewhere"])
        XCTAssertFalse(analyzer.digestRequests.contains("elsewhere"), "reading it would mean downloading it")
        XCTAssertFalse(analyzer.hashRequests.contains("elsewhere"))
        XCTAssertTrue(
            result.groups.isEmpty,
            "a match that only holds if we download the other half is not a match we can act on"
        )
    }

    func testUnreadableItemsAreSkippedRatherThanGuessedAt() async throws {
        let items = [
            Fixtures.item("a", bytes: 100, width: 10, height: 10),
            Fixtures.item("b", bytes: 100, width: 10, height: 10)
        ]
        let analyzer = StubAnalyzer(digests: ["a": .digest(digest(5)), "b": .unavailable])
        let result = try await ScanPipeline(analyzer: analyzer).run(items: items)
        XCTAssertTrue(result.groups.isEmpty)
    }

    // MARK: - Perceptual

    func testCloseOnBothFingerprintsWithSameFramingIsNearExact() async throws {
        let items = [
            Fixtures.item("original", bytes: 6_000_000, width: 4000, height: 3000),
            Fixtures.item("resend", bytes: 400_000, width: 1600, height: 1200)
        ]
        let analyzer = StubAnalyzer(hashes: [
            "original": PerceptualHashes(dHash: baseD, pHash: baseP),
            "resend": PerceptualHashes(dHash: flipping(baseD, bits: 3), pHash: flipping(baseP, bits: 3))
        ])
        let result = try await ScanPipeline(analyzer: analyzer).run(items: items)

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].relation, .nearExact)
        XCTAssertEqual(result.groups[0].seedID, "original", "the higher-resolution copy seeds the group")
        XCTAssertEqual(result.candidates.map(\.id), ["resend"])
        XCTAssertEqual(result.candidates[0].tier, .inferiorCopy)
    }

    /// One fingerprint agreeing is not evidence. This is the test that stops unrelated photos
    /// from reaching a deletion list.
    func testOneFingerprintAgreeingIsNotEnough() async throws {
        let items = [
            Fixtures.item("a", bytes: 1_000, width: 4000, height: 3000),
            Fixtures.item("b", bytes: 2_000, width: 4000, height: 3000)
        ]
        let analyzer = StubAnalyzer(hashes: [
            "a": PerceptualHashes(dHash: baseD, pHash: baseP),
            "b": PerceptualHashes(dHash: flipping(baseD, bits: 2), pHash: flipping(baseP, bits: 40))
        ])
        let result = try await ScanPipeline(analyzer: analyzer).run(items: items)
        XCTAssertTrue(result.groups.isEmpty)
    }

    func testDifferentFramingIsDemotedToSimilar() async throws {
        let items = [
            Fixtures.item("wide", bytes: 1_000, width: 4000, height: 2000),
            Fixtures.item("square", bytes: 2_000, width: 3000, height: 3000)
        ]
        let analyzer = StubAnalyzer(hashes: [
            "wide": PerceptualHashes(dHash: baseD, pHash: baseP),
            "square": PerceptualHashes(dHash: flipping(baseD, bits: 2), pHash: flipping(baseP, bits: 2))
        ])
        let result = try await ScanPipeline(analyzer: analyzer).run(items: items)

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].relation, .similar, "a different crop is a different photo")
        XCTAssertTrue(result.candidates.allSatisfy { !$0.isPreSelected })
    }

    func testFarApartImagesProduceNothing() async throws {
        let items = [
            Fixtures.item("a", bytes: 1_000, width: 100, height: 100),
            Fixtures.item("b", bytes: 2_000, width: 100, height: 100)
        ]
        let analyzer = StubAnalyzer(hashes: [
            "a": PerceptualHashes(dHash: 0, pHash: 0),
            "b": PerceptualHashes(dHash: UInt64.max, pHash: UInt64.max)
        ])
        let result = try await ScanPipeline(analyzer: analyzer).run(items: items)
        XCTAssertTrue(result.groups.isEmpty)
    }

    func testAnExactDuplicateIsNotAlsoFingerprinted() async throws {
        let items = [
            Fixtures.item("a", bytes: 100, width: 10, height: 10),
            Fixtures.item("b", bytes: 100, width: 10, height: 10)
        ]
        let analyzer = StubAnalyzer(digests: ["a": .digest(digest(7)), "b": .digest(digest(7))])
        _ = try await ScanPipeline(analyzer: analyzer).run(items: items)
        XCTAssertTrue(analyzer.hashRequests.isEmpty, "byte equality already settled it")
    }

    // MARK: - Whole-run invariants

    func testNoItemEverLandsInTwoGroups() async throws {
        var items: [MediaItem] = []
        var hashes: [String: PerceptualHashes] = [:]

        // A chain of photos each a few bits from the next, which is exactly the shape that
        // makes a naive clusterer merge everything into one bucket.
        for index in 0..<12 {
            let id = "chain-\(index)"
            items.append(Fixtures.item(id, bytes: Int64(1_000 + index), width: 4000, height: 3000))
            hashes[id] = PerceptualHashes(
                dHash: flipping(baseD, bits: index),
                pHash: flipping(baseP, bits: index)
            )
        }

        let result = try await ScanPipeline(analyzer: StubAnalyzer(hashes: hashes)).run(items: items)

        var seen = Set<String>()
        for group in result.groups {
            for id in group.itemIDs {
                XCTAssertTrue(seen.insert(id).inserted, "\(id) was grouped twice")
            }
        }
    }

    func testEveryScanResultPassesTheCleanupValidator() async throws {
        var items: [MediaItem] = []
        var digests: [String: ContentDigestResult] = [:]
        var hashes: [String: PerceptualHashes] = [:]
        var rng = SplitMix64(seed: 5150)

        for index in 0..<40 {
            let id = "item-\(index)"
            items.append(
                Fixtures.item(
                    id,
                    bytes: Int64(index % 7 == 0 ? 5_000 : 5_000 + index),
                    width: 4000,
                    height: 3000,
                    favorite: Bool.random(using: &rng)
                )
            )
            digests[id] = .digest(digest(UInt8(index % 5)))
            hashes[id] = PerceptualHashes(
                dHash: flipping(baseD, bits: index % 14),
                pHash: flipping(baseP, bits: index % 14)
            )
        }

        let result = try await ScanPipeline(
            analyzer: StubAnalyzer(digests: digests, hashes: hashes)
        ).run(items: items)

        let violations = CleanupValidator.validate(
            selection: Set(result.candidates.filter(\.isPreSelected).map(\.id)),
            decisions: result.decisions,
            knownItemIDs: Set(result.items.keys)
        )
        XCTAssertEqual(violations, [])
    }

    func testEmptyLibraryScansToNothing() async throws {
        let result = try await ScanPipeline(analyzer: StubAnalyzer()).run(items: [])
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertEqual(result.reclaimableBytes, 0)
    }

    func testProgressReachesEveryStageAndNeverExceedsItsTotal() async throws {
        let items = [
            Fixtures.item("a", bytes: 100, width: 10, height: 10),
            Fixtures.item("b", bytes: 100, width: 10, height: 10),
            Fixtures.item("c", bytes: 55, width: 10, height: 10)
        ]
        let analyzer = StubAnalyzer(
            digests: ["a": .digest(digest(1)), "b": .digest(digest(2))],
            hashes: ["c": PerceptualHashes(dHash: 1, pHash: 1)]
        )

        let recorder = ProgressRecorder()
        _ = try await ScanPipeline(analyzer: analyzer).run(items: items) { update in
            recorder.record(update)
        }

        let updates = recorder.updates
        XCTAssertTrue(updates.contains { $0.stage == .bucketing })
        XCTAssertTrue(updates.contains { $0.stage == .planning })
        for update in updates {
            XCTAssertLessThanOrEqual(update.completed, update.total)
            XCTAssertLessThanOrEqual(update.fraction, 1)
        }
    }

    func testCancellationStopsTheScan() async {
        let items = (0..<60).map { Fixtures.item("i\($0)", bytes: 100, width: 10, height: 10) }
        let pipeline = ScanPipeline(analyzer: StubAnalyzer(delay: .milliseconds(20)))

        let task = Task { try await pipeline.run(items: items) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("a cancelled scan must not return a result")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScanProgress] = []

    func record(_ progress: ScanProgress) {
        lock.lock(); defer { lock.unlock() }
        storage.append(progress)
    }

    var updates: [ScanProgress] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

/// Analyzer that can answer for video as well as stills.
final class StubVideoAnalyzer: AssetAnalyzing, @unchecked Sendable {

    private let signatures: [String: VideoSignature]
    private let lock = NSLock()
    private var _sampled: [String] = []

    init(signatures: [String: VideoSignature]) {
        self.signatures = signatures
    }

    var sampled: [String] {
        lock.lock(); defer { lock.unlock() }
        return _sampled
    }

    func contentDigest(for item: MediaItem) async -> ContentDigestResult { .unavailable }

    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? { nil }

    func videoSignature(for item: MediaItem) async -> VideoSignature? {
        lock.lock()
        _sampled.append(item.id)
        lock.unlock()
        return signatures[item.id]
    }
}

final class VideoScanTests: XCTestCase {

    private let base: [UInt64] = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA]

    private func video(_ id: String, seconds: Double, width: Int = 1920, height: Int = 1080, bytes: Int64 = 500_000) -> MediaItem {
        MediaItem(
            id: id,
            source: .photoLibrary,
            kind: .video,
            displayName: "\(id).MOV",
            byteSize: bytes,
            pixelWidth: width,
            pixelHeight: height,
            duration: seconds
        )
    }

    private func nudged(_ frames: [UInt64], bits: Int) -> [UInt64] {
        frames.map { frame in
            var value = frame
            for bit in 0..<bits { value ^= (UInt64(1) << UInt64(bit)) }
            return value
        }
    }

    // MARK: - Prefilter

    func testOnlyVideosOfSimilarLengthArePaired() {
        let items = [
            video("a", seconds: 30.0),
            video("b", seconds: 30.3),
            video("c", seconds: 95.0)
        ]
        let pairs = ScanPipeline.videoCandidatePairs(items, tolerance: 0.5)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual([pairs[0].a, pairs[0].b].sorted(), ["a", "b"])
    }

    func testStillsAreNeverPairedAsVideo() {
        let items = [
            MediaItem(id: "photo1", source: .photoLibrary, kind: .image, duration: 0),
            MediaItem(id: "photo2", source: .photoLibrary, kind: .image, duration: 0)
        ]
        XCTAssertTrue(ScanPipeline.videoCandidatePairs(items, tolerance: 0.5).isEmpty)
    }

    func testVideosWithNoDurationAreSkipped() {
        let items = [video("a", seconds: 0), video("b", seconds: 0)]
        XCTAssertTrue(ScanPipeline.videoCandidatePairs(items, tolerance: 0.5).isEmpty)
    }

    /// Duration alone is a weak filter: a camera roll of fifteen-second exports is one giant
    /// run, and every pair in it used to be opened and sampled.
    func testVideosOfDifferentShapesAreNotPaired() {
        let items = [
            video("wide", seconds: 10.0, width: 1920, height: 1080),
            video("tall", seconds: 10.1, width: 1080, height: 1920)
        ]
        XCTAssertTrue(ScanPipeline.videoCandidatePairs(items, tolerance: 0.5).isEmpty)
    }

    /// Unknown proportions are not evidence of difference. A video in a granted folder carries
    /// none until something opens it, and excluding those unexamined would switch video
    /// matching off for the whole Files source.
    func testAVideoWithNoKnownShapeIsStillPaired() {
        let items = [
            video("known", seconds: 10.0, width: 1920, height: 1080),
            video("unknown", seconds: 10.1, width: 0, height: 0)
        ]
        XCTAssertEqual(ScanPipeline.videoCandidatePairs(items, tolerance: 0.5).count, 1)
    }

    func testEveryVideoInACloseRunIsPairedWithEveryOther() {
        let items = [
            video("a", seconds: 10.0),
            video("b", seconds: 10.2),
            video("c", seconds: 10.4)
        ]
        let pairs = ScanPipeline.videoCandidatePairs(items, tolerance: 0.5)
        XCTAssertEqual(pairs.count, 3)
    }

    // MARK: - Whole scan

    func testARecodedVideoIsFoundAndTheBetterOneKept() async throws {
        let items = [
            video("original", seconds: 95.0, width: 1920, height: 1080, bytes: 620_000_000),
            video("sent", seconds: 95.2, width: 1280, height: 720, bytes: 180_000_000)
        ]
        let analyzer = StubVideoAnalyzer(signatures: [
            "original": VideoSignature(frameHashes: base),
            "sent": VideoSignature(frameHashes: nudged(base, bits: 2))
        ])

        let result = try await ScanPipeline(analyzer: analyzer, throttle: UnthrottledScan())
            .run(items: items)

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].relation, .nearExact)
        XCTAssertEqual(result.candidates.map(\.id), ["sent"])
        XCTAssertEqual(result.candidates[0].tier, .inferiorCopy, "fewer pixels, same footage")
        XCTAssertTrue(result.candidates[0].isPreSelected)
    }

    func testDifferentFootageOfTheSameLengthIsNotAMatch() async throws {
        let items = [video("a", seconds: 30), video("b", seconds: 30.1, bytes: 400_000)]
        let analyzer = StubVideoAnalyzer(signatures: [
            "a": VideoSignature(frameHashes: base),
            "b": VideoSignature(frameHashes: base.map { _ in UInt64.max })
        ])

        let result = try await ScanPipeline(analyzer: analyzer, throttle: UnthrottledScan())
            .run(items: items)
        XCTAssertTrue(result.groups.isEmpty)
    }

    /// The veto that matters: footage that averages close but contains one completely
    /// different scene is a different video, and averaging would hide that.
    func testOneWildlyDifferentSceneVetoesTheMatch() async throws {
        let items = [video("a", seconds: 30), video("b", seconds: 30.1, bytes: 400_000)]
        var broken = base
        broken[4] = ~base[4]

        let analyzer = StubVideoAnalyzer(signatures: [
            "a": VideoSignature(frameHashes: base),
            "b": VideoSignature(frameHashes: broken)
        ])

        let result = try await ScanPipeline(analyzer: analyzer, throttle: UnthrottledScan())
            .run(items: items)
        XCTAssertTrue(result.groups.isEmpty)
    }

    func testVideosFarApartInLengthAreNeverEvenOpened() async throws {
        let items = [video("a", seconds: 30), video("b", seconds: 240, bytes: 400_000)]
        let analyzer = StubVideoAnalyzer(signatures: [
            "a": VideoSignature(frameHashes: base),
            "b": VideoSignature(frameHashes: base)
        ])

        _ = try await ScanPipeline(analyzer: analyzer, throttle: UnthrottledScan()).run(items: items)
        XCTAssertTrue(analyzer.sampled.isEmpty, "duration alone ruled them out, so nothing was sampled")
    }

    func testAVideoWithoutASignatureIsSimplyNotMatched() async throws {
        let items = [video("a", seconds: 30), video("b", seconds: 30.1, bytes: 400_000)]
        let analyzer = StubVideoAnalyzer(signatures: ["a": VideoSignature(frameHashes: base)])

        let result = try await ScanPipeline(analyzer: analyzer, throttle: UnthrottledScan())
            .run(items: items)
        XCTAssertTrue(result.groups.isEmpty)
    }

    func testADifferentAspectRatioIsDemotedRatherThanCalledTheSameShot() async throws {
        let items = [
            video("wide", seconds: 30, width: 1920, height: 1080),
            video("square", seconds: 30.1, width: 1080, height: 1080, bytes: 400_000)
        ]
        let analyzer = StubVideoAnalyzer(signatures: [
            "wide": VideoSignature(frameHashes: base),
            "square": VideoSignature(frameHashes: nudged(base, bits: 2))
        ])

        let result = try await ScanPipeline(analyzer: analyzer, throttle: UnthrottledScan())
            .run(items: items)

        XCTAssertEqual(result.groups.first?.relation, .similar)
        XCTAssertTrue(result.candidates.allSatisfy { !$0.isPreSelected })
    }

    func testVideoResultsStillPassTheCleanupValidator() async throws {
        var items: [MediaItem] = []
        var signatures: [String: VideoSignature] = [:]
        for index in 0..<8 {
            let id = "v\(index)"
            items.append(video(id, seconds: 40 + Double(index) * 0.2, bytes: Int64(900_000 - index)))
            signatures[id] = VideoSignature(frameHashes: nudged(base, bits: index))
        }

        let result = try await ScanPipeline(
            analyzer: StubVideoAnalyzer(signatures: signatures),
            throttle: UnthrottledScan()
        ).run(items: items)

        let violations = CleanupValidator.validate(
            selection: Set(result.candidates.filter(\.isPreSelected).map(\.id)),
            decisions: result.decisions,
            knownItemIDs: Set(result.items.keys)
        )
        XCTAssertEqual(violations, [])

        var seen = Set<String>()
        for group in result.groups {
            for id in group.itemIDs {
                XCTAssertTrue(seen.insert(id).inserted, "\(id) was grouped twice")
            }
        }
    }
}
