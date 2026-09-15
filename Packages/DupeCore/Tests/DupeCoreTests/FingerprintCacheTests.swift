import XCTest
@testable import DupeCore

/// Counts how often the expensive work is actually asked for.
private final class CountingAnalyzer: AssetAnalyzing, @unchecked Sendable {

    private let lock = NSLock()
    private var _digestCalls = 0
    private var _hashCalls = 0
    private var _signatureCalls = 0

    var digestCalls: Int { lock.lock(); defer { lock.unlock() }; return _digestCalls }
    var hashCalls: Int { lock.lock(); defer { lock.unlock() }; return _hashCalls }
    var signatureCalls: Int { lock.lock(); defer { lock.unlock() }; return _signatureCalls }

    func contentDigest(for item: MediaItem) async -> ContentDigestResult {
        lock.lock(); _digestCalls += 1; lock.unlock()
        return .digest(ContentDigest(bytes: Array(item.id.utf8)))
    }

    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
        lock.lock(); _hashCalls += 1; lock.unlock()
        return PerceptualHashes(dHash: 7, pHash: 9)
    }

    /// The shape a Vision-backed analyzer has: one decode, both fingerprints.
    func imageFingerprint(for item: MediaItem) async -> ImageFingerprint? {
        lock.lock(); _hashCalls += 1; lock.unlock()
        return ImageFingerprint(
            hashes: PerceptualHashes(dHash: 7, pHash: 9),
            featurePrint: FeaturePrint(descriptor: "vision.revision2", elements: [1, 0, 0, 0])
        )
    }

    func videoSignature(for item: MediaItem) async -> VideoSignature? {
        lock.lock(); _signatureCalls += 1; lock.unlock()
        return VideoSignature(frameHashes: [1, 2, 3, 4, 5])
    }
}

private struct FailingAnalyzer: AssetAnalyzing {
    func contentDigest(for item: MediaItem) async -> ContentDigestResult { .unavailable }
    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? { nil }
}

private struct CloudAnalyzer: AssetAnalyzing {
    func contentDigest(for item: MediaItem) async -> ContentDigestResult { .cloudOnly }
    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? { nil }
}

final class ContentVersionTests: XCTestCase {

    func testVersionChangesWithTheThingsThatChangeBytes() {
        let base = Fixtures.item("a", bytes: 100, width: 10, height: 10)

        var resized = base
        resized.byteSize = 101
        XCTAssertNotEqual(resized.contentVersion, base.contentVersion)

        var recropped = base
        recropped.pixelWidth = 11
        XCTAssertNotEqual(recropped.contentVersion, base.contentVersion)

        var edited = base
        edited.modificationDate = Date(timeIntervalSince1970: 500)
        XCTAssertNotEqual(edited.contentVersion, base.contentVersion)

        var liveVideoGrew = base
        liveVideoGrew.pairedVideoByteSize = 5
        XCTAssertNotEqual(liveVideoGrew.contentVersion, base.contentVersion)
    }

    func testVersionIgnoresThingsThatCannotChangeBytes() {
        let base = Fixtures.item("a", bytes: 100)

        var favourited = base
        favourited.isFavorite = true
        XCTAssertEqual(favourited.contentVersion, base.contentVersion, "a star does not re-encode a photo")

        var filed = base
        filed.albumCount = 3
        XCTAssertEqual(filed.contentVersion, base.contentVersion)
    }
}

final class FingerprintCacheTests: XCTestCase {

    private let item = Fixtures.item("a", bytes: 100, width: 10, height: 10)

    func testASecondScanOfAnUnchangedItemReadsNothing() async {
        let analyzer = CountingAnalyzer()
        let caching = CachingAnalyzer(base: analyzer, cache: FingerprintCache())

        _ = await caching.contentDigest(for: item)
        _ = await caching.perceptualHashes(for: item)
        _ = await caching.videoSignature(for: item)

        _ = await caching.contentDigest(for: item)
        _ = await caching.perceptualHashes(for: item)
        _ = await caching.videoSignature(for: item)

        XCTAssertEqual(analyzer.digestCalls, 1)
        XCTAssertEqual(analyzer.hashCalls, 1)
        XCTAssertEqual(analyzer.signatureCalls, 1)
    }

    func testTheCachedAnswerIsTheSameAnswer() async {
        let caching = CachingAnalyzer(base: CountingAnalyzer(), cache: FingerprintCache())

        let first = await caching.contentDigest(for: item)
        let second = await caching.contentDigest(for: item)
        XCTAssertEqual(first, second)

        let firstHashes = await caching.perceptualHashes(for: item)
        let secondHashes = await caching.perceptualHashes(for: item)
        XCTAssertEqual(firstHashes, secondHashes)
    }

    /// The property the whole cache rests on: bytes that changed invalidate everything held
    /// against them. A stale fingerprint would describe a file that no longer exists.
    func testChangedBytesInvalidateEveryFingerprint() async {
        let analyzer = CountingAnalyzer()
        let caching = CachingAnalyzer(base: analyzer, cache: FingerprintCache())

        _ = await caching.contentDigest(for: item)
        _ = await caching.perceptualHashes(for: item)

        var edited = item
        edited.byteSize = 101

        _ = await caching.contentDigest(for: edited)
        _ = await caching.perceptualHashes(for: edited)

        XCTAssertEqual(analyzer.digestCalls, 2)
        XCTAssertEqual(analyzer.hashCalls, 2, "a hash held against the old bytes cannot be reused")
    }

    func testStoringOneFingerprintDoesNotResurrectStaleSiblings() async {
        let cache = FingerprintCache()
        await cache.store(digest: ContentDigest(bytes: [1]), for: "a", contentVersion: "v1")
        await cache.store(hashes: PerceptualHashes(dHash: 1, pHash: 1), for: "a", contentVersion: "v2")

        let record = await cache.record(for: "a")
        XCTAssertEqual(record?.contentVersion, "v2")
        XCTAssertNil(record?.digest, "the digest belonged to the previous version")
        XCTAssertNotNil(record?.hashes)
    }

    func testUnreadableItemsAreNotCachedAsAnswers() async {
        let cache = FingerprintCache()
        let caching = CachingAnalyzer(base: FailingAnalyzer(), cache: cache)

        _ = await caching.contentDigest(for: item)
        _ = await caching.perceptualHashes(for: item)

        let stored = await cache.record(for: item.id)
        XCTAssertNil(stored, "a failure is not a result worth remembering")
    }

    func testCloudOnlyResultsAreNotCached() async {
        let cache = FingerprintCache()
        _ = await CachingAnalyzer(base: CloudAnalyzer(), cache: cache).contentDigest(for: item)

        let stored = await cache.record(for: item.id)
        XCTAssertNil(stored, "the original was never read, so there is nothing to remember")
    }

    func testPruningForgetsItemsThatLeftTheLibrary() async {
        let cache = FingerprintCache()
        await cache.store(digest: ContentDigest(bytes: [1]), for: "stays", contentVersion: "v")
        await cache.store(digest: ContentDigest(bytes: [2]), for: "goes", contentVersion: "v")

        await cache.prune(keeping: ["stays"])

        let kept = await cache.record(for: "stays")
        let gone = await cache.record(for: "goes")
        XCTAssertNotNil(kept)
        XCTAssertNil(gone)
    }

    /// Was a JSON round trip. The format moved to `FingerprintArchive` when a record started
    /// carrying a 768-element vector; the property this test is about did not move.
    func testTheCacheSurvivesATripToDiskAndBack() throws {
        let record = FingerprintRecord(
            contentVersion: "v1",
            digest: ContentDigest(bytes: [1, 2, 3]),
            hashes: PerceptualHashes(dHash: 42, pHash: 99),
            signature: VideoSignature(frameHashes: [7, 8, 9])
        )
        let data = FingerprintArchive.data(for: ["a": record])
        let restored = FingerprintArchive.records(from: data)
        XCTAssertEqual(restored?["a"], record)
    }

    func testAWholeScanReReadsNothingTheSecondTime() async throws {
        let items = [
            Fixtures.item("a", bytes: 100, width: 10, height: 10),
            Fixtures.item("b", bytes: 100, width: 10, height: 10),
            Fixtures.item("c", bytes: 55, width: 10, height: 10)
        ]
        let analyzer = CountingAnalyzer()
        let pipeline = ScanPipeline(
            analyzer: CachingAnalyzer(base: analyzer, cache: FingerprintCache()),
            throttle: UnthrottledScan()
        )

        let first = try await pipeline.run(items: items)
        let callsAfterFirst = analyzer.digestCalls + analyzer.hashCalls

        let second = try await pipeline.run(items: items)

        XCTAssertEqual(analyzer.digestCalls + analyzer.hashCalls, callsAfterFirst, "nothing was re-read")
        XCTAssertEqual(first.groups.count, second.groups.count)
        XCTAssertEqual(first.reclaimableBytes, second.reclaimableBytes)
    }

    // MARK: - Feature prints

    func testAPrintIsReadBackRatherThanRecomputed() async {
        let analyzer = CountingAnalyzer()
        let caching = CachingAnalyzer(base: analyzer, cache: FingerprintCache())
        let item = Fixtures.item("a")

        let first = await caching.imageFingerprint(for: item)
        let second = await caching.imageFingerprint(for: item)

        XCTAssertEqual(analyzer.hashCalls, 1, "the print is the expensive half; it must be computed once")
        XCTAssertEqual(first?.featurePrint, second?.featurePrint)
        XCTAssertNotNil(first?.featurePrint)
    }

    func testChangedBytesInvalidateThePrintToo() async {
        let analyzer = CountingAnalyzer()
        let caching = CachingAnalyzer(base: analyzer, cache: FingerprintCache())

        _ = await caching.imageFingerprint(for: Fixtures.item("a", bytes: 100))
        _ = await caching.imageFingerprint(for: Fixtures.item("a", bytes: 200))

        XCTAssertEqual(analyzer.hashCalls, 2, "a print describes the bytes it was computed from and nothing else")
    }

    func testAnEntryFromBeforePrintsExistedIsNotTreatedAsAComplete() async {
        // The shape every upgrading install is in: hashes cached by the old build, no print.
        // Handing that back would pin the library to the old engine one asset at a time, and
        // nothing about it would look wrong.
        let cache = FingerprintCache()
        let item = Fixtures.item("a")
        await cache.store(hashes: PerceptualHashes(dHash: 7, pHash: 9), for: item.id, contentVersion: item.contentVersion)

        let analyzer = CountingAnalyzer()
        let fingerprint = await CachingAnalyzer(base: analyzer, cache: cache).imageFingerprint(for: item)

        XCTAssertEqual(analyzer.hashCalls, 1, "the print is missing, so the decode has to happen")
        XCTAssertNotNil(fingerprint?.featurePrint)
    }

    func testAnAnalyzerWithoutPrintsNeverErasesOneAlreadyStored() async {
        let cache = FingerprintCache()
        let item = Fixtures.item("a")
        _ = await CachingAnalyzer(base: CountingAnalyzer(), cache: cache).imageFingerprint(for: item)

        // Stored straight into the cache rather than through the wrapper: the wrapper would
        // find the record complete and never write, which is the right behaviour and the wrong
        // test. The two halves of this app use two analyzers and only one of them has Vision.
        await cache.store(
            fingerprint: ImageFingerprint(hashes: PerceptualHashes(dHash: 3, pHash: 4)),
            for: item.id,
            contentVersion: item.contentVersion
        )

        let record = await cache.record(for: item.id)
        XCTAssertEqual(record?.hashes, PerceptualHashes(dHash: 3, pHash: 4), "the hashes are the fresh ones")
        XCTAssertNotNil(
            record?.featurePrint,
            "a source that cannot produce prints must not spend the one the library already paid for"
        )
    }

    func testAnAnalyzerWithoutPrintsStillFillsTheHashesInTheCache() async {
        // The old shape: `perceptualHashes` and nothing else. The cache must not start storing
        // empty prints over it, or the next build's print never gets computed.
        struct HashesOnly: AssetAnalyzing {
            func contentDigest(for item: MediaItem) async -> ContentDigestResult { .unavailable }
            func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
                PerceptualHashes(dHash: 1, pHash: 2)
            }
        }

        let cache = FingerprintCache()
        let item = Fixtures.item("a")
        _ = await CachingAnalyzer(base: HashesOnly(), cache: cache).imageFingerprint(for: item)

        let record = await cache.record(for: item.id)
        XCTAssertEqual(record?.hashes, PerceptualHashes(dHash: 1, pHash: 2))
        XCTAssertNil(record?.featurePrint)
    }
}

final class ScanPauseTests: XCTestCase {

    func testAHeldScanMakesNoProgressUntilItIsResumed() async throws {
        let gate = ScanPauseGate(paused: true)
        let analyzer = CountingAnalyzer()
        let items = (0..<6).map { Fixtures.item("i\($0)", bytes: 100, width: 10, height: 10) }

        let task = Task {
            try await ScanPipeline(analyzer: analyzer, throttle: UnthrottledScan(), pause: gate)
                .run(items: items)
        }

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(analyzer.digestCalls, 0, "a held scan must not be reading")

        gate.resume()
        let result = try await task.value
        XCTAssertGreaterThan(analyzer.digestCalls, 0)
        XCTAssertEqual(result.groups.count, 1, "and it finishes the work it was holding")
    }

    func testAScanCancelledWhileHeldDoesNotWaitForever() async {
        let gate = ScanPauseGate(paused: true)
        let items = (0..<6).map { Fixtures.item("i\($0)", bytes: 100, width: 10, height: 10) }

        let task = Task {
            try await ScanPipeline(analyzer: CountingAnalyzer(), throttle: UnthrottledScan(), pause: gate)
                .run(items: items)
        }

        try? await Task.sleep(for: .milliseconds(200))
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

    func testTheGateReportsItsOwnState() async {
        let gate = ScanPauseGate()
        var paused = gate.paused
        XCTAssertFalse(paused)

        gate.pause()
        paused = gate.paused
        XCTAssertTrue(paused)

        gate.resume()
        paused = gate.paused
        XCTAssertFalse(paused)
    }

    func testNothingHoldsAnUnpausedScan() async {
        await NeverPaused().waitUntilResumed()
        await ScanPauseGate().waitUntilResumed()
    }
}
