import XCTest
import DupeCore
@testable import DupeSpace

/// The engine, on its own, with nothing of the screen attached.
///
/// Everything here is about *sequencing*, because that is the only thing this type can get
/// wrong that the old `ScanViewModel` could not: the work moved off the main actor, so the
/// controls now cross an isolation boundary and the order they arrive in stopped being free.
/// `ScanPausing.swift:12-22` records what that cost the last time it was got wrong.
final class ScanManagerTests: XCTestCase {

    // MARK: - Reading the stream

    /// Drains a scan's stream into an array, giving up rather than hanging.
    ///
    /// A hang is the failure mode this whole suite is watching for — a gate left holding has no
    /// other symptom — and `XCTest`'s own timeout kills the process without saying which
    /// assertion was waiting. This gives up with the events it did see.
    private func drain(
        _ stream: AsyncStream<ScanEvent>,
        timeout: Duration = .seconds(30)
    ) async -> [ScanEvent] {
        let log = EventLog()
        let pump = Task { for await event in stream { await log.append(event) } }
        let deadline = Task {
            try? await Task.sleep(for: timeout)
            pump.cancel()
        }
        await pump.value
        deadline.cancel()
        return await log.events
    }

    private actor EventLog {
        private(set) var events: [ScanEvent] = []
        func append(_ event: ScanEvent) { events.append(event) }
    }

    private func slowAnalyzer(_ step: Duration = .milliseconds(40)) -> StubAssetAnalyzer {
        StubAssetAnalyzer(digests: [:], hashes: [:], stepDelay: step)
    }

    // MARK: - Finishing

    func testAScanEndsWithTheResultItFound() async {
        let manager = ScanManager(analyzer: StubAssetAnalyzer.uiTestFixture())
        let events = await drain(
            manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)
        )

        guard let result = events.compactMap(\.finishedResult).first else {
            return XCTFail("the stream ended without a result: \(events)")
        }
        XCTAssertTrue(result.candidates.contains { $0.id == "video-holiday-copy" })
        XCTAssertNil(events.compactMap(\.failureMessage).first)
    }

    func testProgressIsReportedBeforeTheResult() async {
        let manager = ScanManager(analyzer: StubAssetAnalyzer.uiTestFixture())
        let events = await drain(
            manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)
        )

        guard let finishIndex = events.firstIndex(where: { $0.finishedResult != nil }) else {
            return XCTFail("the stream ended without a result")
        }
        XCTAssertTrue(
            events[..<finishIndex].contains { $0.progressValue != nil },
            "a scan that reported nothing until it was over has nothing to draw"
        )
        XCTAssertEqual(finishIndex, events.count - 1, "the result is the last thing said")
    }

    /// An empty library is not an error, and must not be reported as one.
    func testScanningNothingFinishesRatherThanFailing() async {
        let manager = ScanManager(analyzer: StubAssetAnalyzer.uiTestFixture())
        let events = await drain(manager.start(items: [], configuration: .default))

        XCTAssertNotNil(events.compactMap(\.finishedResult).first)
        XCTAssertTrue(events.compactMap(\.failureMessage).isEmpty)
    }

    // MARK: - Cancelling

    /// The reason `start` is synchronous.
    ///
    /// Were it isolated to the actor, reaching it would need an `await`, and this cancel would
    /// arrive at an empty task box: nothing to cancel, then the scan starts anyway and runs to
    /// the end. The caller on the main actor issues these two calls with no suspension between
    /// them, so the manager has to be able to hear them in that order.
    func testCancellingInTheSameTurnAsStartingStopsTheScan() async {
        let manager = ScanManager(analyzer: slowAnalyzer(.milliseconds(50)))

        let stream = manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)
        manager.cancel()

        let events = await drain(stream)
        XCTAssertTrue(events.contains(where: \.isCancelled), "the scan was not cancelled: \(events)")
        XCTAssertTrue(events.compactMap(\.finishedResult).isEmpty, "a cancelled scan has no result")
    }

    func testCancellingAHeldScanLetsItGo() async {
        let manager = ScanManager(analyzer: slowAnalyzer(.milliseconds(30)))
        let stream = manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)

        manager.pause()
        manager.cancel()

        let events = await drain(stream)
        XCTAssertTrue(events.contains(where: \.isCancelled))
        XCTAssertTrue(events.compactMap(\.finishedResult).isEmpty)
    }

    /// Cancelling is not failing. The screen tells them apart, and one of them says the word
    /// "failed" over their photo library.
    func testACancelledScanIsNotReportedAsAFailure() async {
        let manager = ScanManager(analyzer: slowAnalyzer(.milliseconds(50)))
        let stream = manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)
        manager.cancel()

        let events = await drain(stream)
        XCTAssertTrue(events.compactMap(\.failureMessage).isEmpty, "cancelling is not an error")
    }

    // MARK: - Holding

    func testAHeldScanStopsReportingAndThenFinishesTheWork() async {
        let manager = ScanManager(analyzer: slowAnalyzer(.milliseconds(40)))
        let log = EventLog()
        let stream = manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)
        let pump = Task { for await event in stream { await log.append(event) } }

        // Far enough in that an unheld scan is certainly still reporting.
        try? await Task.sleep(for: .milliseconds(200))
        manager.pause()

        // Two readings, taken after the in-flight item has had time to land.
        try? await Task.sleep(for: .milliseconds(400))
        let first = await log.events.count
        try? await Task.sleep(for: .milliseconds(500))
        let second = await log.events.count

        XCTAssertEqual(first, second, "a held scan must not report progress")
        let whileHeld = await log.events
        XCTAssertTrue(
            whileHeld.compactMap(\.finishedResult).isEmpty,
            "a held scan has not finished"
        )

        manager.resume()
        let deadline = Task { try? await Task.sleep(for: .seconds(30)); pump.cancel() }
        await pump.value
        deadline.cancel()

        let afterResuming = await log.events
        XCTAssertNotNil(
            afterResuming.compactMap(\.finishedResult).first,
            "resuming has to finish the work, not discard it"
        )
    }

    /// The bug `ScanPauseGate` was made a lock to prevent, asked of the manager instead.
    ///
    /// Two taps land on the main actor with nothing between them. If either control took a hop
    /// to reach the gate, the pair could arrive the other way round: the gate would be left
    /// holding, every worker parked, and the only symptom a scan that never ends — which is
    /// what draining this stream would do.
    func testPausingAndResumingInOneTurnLeavesTheScanRunning() async {
        let manager = ScanManager(analyzer: StubAssetAnalyzer.uiTestFixture())
        let stream = manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)

        manager.pause()
        manager.resume()

        let events = await drain(stream, timeout: .seconds(20))
        XCTAssertNotNil(
            events.compactMap(\.finishedResult).first,
            "the scan never finished — the gate was left holding"
        )
    }

    /// Holding is only meaningful against a running scan, and a hold left set would stop the
    /// next one before it read anything.
    func testAScanStartedAfterAStrayPauseStillRuns() async {
        let manager = ScanManager(analyzer: StubAssetAnalyzer.uiTestFixture())
        manager.pause()

        let events = await drain(
            manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default),
            timeout: .seconds(20)
        )
        XCTAssertNotNil(events.compactMap(\.finishedResult).first, "a stale hold outlived its scan")
    }

    // MARK: - The cache

    /// Every record in the cache was earned by reading a file, and stopping early does not
    /// invalidate one of them. This is the behaviour `ScanViewModel` had to be corrected into:
    /// the flush used to sit in the success branch, so cancelling a long first scan threw away
    /// every fingerprint it had computed.
    func testACancelledScanStillWritesDownWhatItLearned() async throws {
        let file = temporaryCacheFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let cache = FileFingerprintCache(fileURL: file)
        await cache.store(digest: ContentDigest(bytes: [1, 2, 3]), for: "ghost", contentVersion: "v1")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "nothing should be on disk until something flushes"
        )

        let manager = ScanManager(analyzer: slowAnalyzer(.milliseconds(50)), cache: cache)
        let stream = manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)
        manager.cancel()
        _ = await drain(stream)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: file.path),
            "a cancelled scan threw away every fingerprint it had computed"
        )
    }

    func testAFinishedScanForgetsItemsTheLibraryNoLongerHas() async {
        let file = temporaryCacheFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let cache = FileFingerprintCache(fileURL: file)
        await cache.store(digest: ContentDigest(bytes: [1, 2, 3]), for: "ghost", contentVersion: "v1")

        let manager = ScanManager(analyzer: StubAssetAnalyzer.uiTestFixture(), cache: cache)
        _ = await drain(manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default))

        let records = await cache.snapshot()
        XCTAssertNil(records["ghost"], "an item the scan never saw is not in the library any more")
    }

    /// Pruning is bounded by the items the scan was given, so a scan that never got through
    /// them must not be allowed to decide what is missing.
    func testACancelledScanDoesNotForgetAnything() async {
        let file = temporaryCacheFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let cache = FileFingerprintCache(fileURL: file)
        await cache.store(digest: ContentDigest(bytes: [1, 2, 3]), for: "ghost", contentVersion: "v1")

        let manager = ScanManager(analyzer: slowAnalyzer(.milliseconds(50)), cache: cache)
        let stream = manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)
        manager.cancel()
        _ = await drain(stream)

        let records = await cache.snapshot()
        XCTAssertNotNil(records["ghost"], "a scan that was stopped does not know what is missing")
    }

    // MARK: - Starting again

    /// Two scans sharing one fingerprint cache would each prune against their own item list.
    /// The screen's own guard stops this, but the guard is on the other side of an isolation
    /// boundary, so the engine holds one too.
    func testStartingAgainStopsTheScanAlreadyRunning() async {
        let manager = ScanManager(analyzer: slowAnalyzer(.milliseconds(50)))
        let first = manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)
        let second = manager.start(items: StubMediaLibrary.sampleItems(), configuration: .default)

        let firstEvents = await drain(first, timeout: .seconds(20))
        XCTAssertTrue(
            firstEvents.compactMap(\.finishedResult).isEmpty,
            "the replaced scan kept running: \(firstEvents)"
        )

        let secondEvents = await drain(second)
        XCTAssertNotNil(secondEvents.compactMap(\.finishedResult).first, "the new scan did not run")
    }

    private func temporaryCacheFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-manager-tests-\(UUID().uuidString).json")
    }
}

/// Reading one case out of the stream. Test-side on purpose: the app never asks a `ScanEvent`
/// what it is, it switches over it.
private extension ScanEvent {

    var progressValue: ScanProgress? {
        if case let .progress(progress) = self { progress } else { nil }
    }

    var finishedResult: ScanResult? {
        if case let .finished(result) = self { result } else { nil }
    }

    var failureMessage: String? {
        if case let .failed(message) = self { message } else { nil }
    }

    var isCancelled: Bool {
        if case .cancelled = self { true } else { false }
    }
}
