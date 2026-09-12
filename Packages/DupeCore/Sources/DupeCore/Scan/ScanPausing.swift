import Foundation

/// Lets a scan be held without being thrown away.
///
/// Cancelling a scan of fifty thousand photos loses everything it had read. Pausing is what a
/// person actually wants when the phone gets warm or a call comes in.
public protocol ScanPausing: Sendable {
    /// Returns once scanning may continue. Returns immediately when nothing is holding it.
    func waitUntilResumed() async
}

public actor ScanPauseGate: ScanPausing {

    /// How often a held scan looks up to see whether it may continue. Coarse on purpose: a
    /// tenth of a second is imperceptible next to a scan, and polling keeps the gate free of
    /// continuation bookkeeping that has to get cancellation exactly right.
    private static let pollInterval = Duration.milliseconds(100)

    private var isPaused: Bool

    public init(paused: Bool = false) {
        isPaused = paused
    }

    public var paused: Bool { isPaused }

    public func pause() { isPaused = true }

    public func resume() { isPaused = false }

    public func waitUntilResumed() async {
        // Cancellation wins over the hold: a paused scan that is then cancelled must not sit
        // there forever waiting for a resume that is never coming.
        while isPaused && !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
        }
    }
}

/// For callers that never pause.
public struct NeverPaused: ScanPausing {
    public init() {}
    public func waitUntilResumed() async {}
}
