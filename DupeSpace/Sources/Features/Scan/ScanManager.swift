import Foundation
import DupeCore

/// Everything a running scan has to say, in the order it says it.
///
/// A stream rather than a set of callbacks because the ordering is the point: the engine runs
/// off the main actor now, and the screen has to be able to trust that a result it has been
/// handed is not overtaken by progress from before it.
enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case finished(ScanResult)
    case cancelled
    case failed(String)
}

/// The engine. Runs the pipeline, minds the task, prunes and flushes the cache, and says what
/// happened — and nothing else.
///
/// It owns no part of the app: no history, no Live Activity, no widget. Those belong to
/// `ScanStore` and stay on the main actor, which is what lets this be an actor at all — every
/// one of them is a `@MainActor` type that an actor could only reach by hopping back.
///
/// **The controls are deliberately synchronous and outside the isolation.** `ScanPausing.swift`
/// records why in full: reached through `await`, two taps issued back to back on the main actor
/// become two unstructured tasks with no order between them, and a pause-then-resume that
/// executes as resume-then-pause leaves the scan held while the screen says it is running.
/// `start` is synchronous for the same family of reason — a `cancel()` issued in the same turn
/// has to find a task to cancel, not an empty box that fills a moment later.
actor ScanManager {

    private let analyzer: any AssetAnalyzing
    private let cache: FileFingerprintCache?

    /// Outside the actor's isolation on purpose — see the note above. Both are already safe to
    /// touch from anywhere: the gate holds a lock, and so does the box.
    private nonisolated let gate = ScanPauseGate()
    private nonisolated let handle = TaskHandleBox()

    init(analyzer: any AssetAnalyzing, cache: FileFingerprintCache? = nil) {
        self.analyzer = analyzer
        self.cache = cache
    }

    nonisolated func pause() { gate.pause() }

    nonisolated func resume() { gate.resume() }

    nonisolated func cancel() {
        // Released first, and genuinely first: a held scan that is cancelled has to be let go
        // before it can notice.
        gate.resume()
        handle.cancel()
    }

    /// Starts a scan and hands back the stream it will report on.
    ///
    /// Synchronous, and the task is in the box before this returns. The gate is released here
    /// rather than rebuilt because it is a `let` living as long as the manager: a hold left set
    /// by a scan that ended while paused would otherwise stop the next one before it read
    /// anything.
    nonisolated func start(
        items: [MediaItem],
        configuration: ScanConfiguration
    ) -> AsyncStream<ScanEvent> {
        gate.resume()

        let (stream, continuation) = AsyncStream<ScanEvent>.makeStream()
        handle.store(
            Task { await self.run(items: items, configuration: configuration, into: continuation) }
        )
        return stream
    }

    private func run(
        items: [MediaItem],
        configuration: ScanConfiguration,
        into continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        let pipeline = ScanPipeline(analyzer: analyzer, configuration: configuration, pause: gate)

        // Throttled at the source, not at the sink. The pipeline reports after every completed
        // item, and a fifty-thousand-photo library reporting fifty thousand times is fifty
        // thousand redraws of a screen that cannot show the difference — while the pipeline is
        // already saturating the device's I/O. A change is worth reporting when it changes the
        // stage or moves the visible percentage; everything else is the same frame drawn again.
        let throttle = ProgressThrottle()
        let onProgress: @Sendable (ScanProgress) -> Void = { update in
            guard throttle.shouldPublish(update) else { return }
            continuation.yield(.progress(update))
        }

        do {
            let scan = try await pipeline.run(items: items, progress: onProgress)
            continuation.yield(.finished(scan))

            // Written once the work is done rather than after every fingerprint: fifty thousand
            // writes of the same file would cost more than the cache saves. The library's own
            // ids bound it, so items that have gone are forgotten — and only a scan that got
            // through them all is entitled to decide what is missing.
            if let cache {
                await cache.prune(keeping: Set(items.map(\.id)))
            }
        } catch is CancellationError {
            continuation.yield(.cancelled)
        } catch {
            continuation.yield(.failed(error.localizedDescription))
        }

        // Flushed on every ending, not just the happy one. It used to sit inside the success
        // branch, so cancelling a forty-minute first scan at ninety-five per cent threw away
        // every fingerprint it had computed and the next launch started from nothing — the
        // exact opposite of what a scan you are allowed to stop is for. Every record in there
        // was earned by reading a file; none of it is invalidated by the scan ending early.
        await cache?.flush()

        continuation.finish()
    }
}

/// The running scan's task, reachable from outside the actor.
///
/// A lock rather than actor state for the same reason the gate is one: `cancel()` is called from
/// a button handler, synchronously, and has to act on whatever is running at that instant.
final class TaskHandleBox: @unchecked Sendable {

    private let lock = NSLock()
    private var task: Task<Void, Never>?

    /// Replacing a scan stops it. Two scans running against one fingerprint cache would each
    /// prune it against their own list of items, and the loser's list is the stale one.
    func store(_ task: Task<Void, Never>) {
        lock.lock()
        let previous = self.task
        self.task = task
        lock.unlock()
        previous?.cancel()
    }

    func cancel() {
        lock.lock()
        let running = task
        task = nil
        lock.unlock()
        running?.cancel()
    }
}

/// Decides which of the pipeline's per-item progress reports are worth reporting at all.
///
/// Called from whatever thread the pipeline happens to be on, once per finished item, so it
/// holds its state under a lock rather than an actor: an actor here would put back a hop onto
/// the hottest path in the app.
///
/// The rule is what the screen can actually show. A stage change always goes through, because
/// the label is the largest thing on the screen. Otherwise the percentage has to move — at one
/// decimal place, which is finer than the bar can draw but coarse enough that a fifty-thousand
/// item stage sends about a thousand updates instead of fifty thousand.
final class ProgressThrottle: @unchecked Sendable {

    private let lock = NSLock()
    private var lastStage: ScanProgress.Stage?
    private var lastTick: Int = -1
    /// The highest `completed` allowed through for the current stage.
    ///
    /// The pipeline reads items concurrently and reports from each worker, so two reports can
    /// arrive here in either order however they were generated. Anything not strictly newer
    /// than what has already gone through is dropped here, where the ordering is still
    /// knowable — otherwise the bar ticks backwards under load, which is the "looks stuck"
    /// symptom this throttle exists to remove.
    private var lastCompleted: Int = -1

    func shouldPublish(_ update: ScanProgress) -> Bool {
        let tick = update.total > 0
            ? Int((Double(update.completed) / Double(update.total)) * 1_000)
            : Int(update.completed)

        lock.lock()
        defer { lock.unlock() }

        // The end of a stage always goes through, so the bar is never left short of the mark
        // it reached.
        let isStageChange = update.stage != lastStage
        let isComplete = update.total > 0 && update.completed >= update.total
        guard isStageChange || isComplete || tick != lastTick else { return false }
        // A new stage resets the count, so "newer" only means anything within one stage.
        guard isStageChange || update.completed > lastCompleted else { return false }

        lastStage = update.stage
        lastTick = tick
        lastCompleted = update.completed
        return true
    }
}
