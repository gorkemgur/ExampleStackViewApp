import Foundation

/// Lets a scan be held without being thrown away.
///
/// Cancelling a scan of fifty thousand photos loses everything it had read. Pausing is what a
/// person actually wants when the phone gets warm or a call comes in.
public protocol ScanPausing: Sendable {
    /// Returns once scanning may continue. Returns immediately when nothing is holding it.
    func waitUntilResumed() async
}

/// Deliberately a lock rather than an actor.
///
/// As an actor, `pause()` and `resume()` could only be reached with `await`, and the caller is
/// a button handler on the main actor — so each tap enqueued `Task { await gate.pause() }`.
/// Two unstructured tasks on the same actor have no guaranteed order between them, so a quick
/// pause-then-resume could execute as resume-then-pause. The gate would be left holding while
/// the screen said the scan was running, every worker parked in `waitUntilResumed`, and the
/// only way out was cancelling the scan — which fired a third unordered task of its own.
///
/// A lock makes the flag settable synchronously, so the last caller wins, which is the whole
/// requirement.
public final class ScanPauseGate: ScanPausing, @unchecked Sendable {

    /// How often a held scan looks up to see whether it may continue. Coarse on purpose: a
    /// tenth of a second is imperceptible next to a scan, and polling keeps the gate free of
    /// continuation bookkeeping that has to get cancellation exactly right.
    private static let pollInterval = Duration.milliseconds(100)

    private let lock = NSLock()
    private var isPaused: Bool

    public init(paused: Bool = false) {
        isPaused = paused
    }

    public var paused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPaused
    }

    public func pause() { setPaused(true) }

    public func resume() { setPaused(false) }

    private func setPaused(_ value: Bool) {
        lock.lock()
        isPaused = value
        lock.unlock()
    }

    public func waitUntilResumed() async {
        // Cancellation wins over the hold: a paused scan that is then cancelled must not sit
        // there forever waiting for a resume that is never coming.
        while paused && !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
        }
    }
}

/// For callers that never pause.
public struct NeverPaused: ScanPausing {
    public init() {}
    public func waitUntilResumed() async {}
}
