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

    func testTheCacheSurvivesAnEncodeAndDecode() throws {
        let record = FingerprintRecord(
            contentVersion: "v1",
            digest: ContentDigest(bytes: [1, 2, 3]),
            hashes: PerceptualHashes(dHash: 42, pHash: 99),
            signature: VideoSignature(frameHashes: [7, 8, 9])
        )
        let data = try JSONEncoder().encode(["a": record])
        let restored = try JSONDecoder().decode([String: FingerprintRecord].self, from: data)
        XCTAssertEqual(restored["a"], record)
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
