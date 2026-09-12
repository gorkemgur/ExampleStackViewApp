import Foundation

/// When a running scan is worth telling the Lock Screen about.
///
/// The pipeline reports progress once per item — tens of thousands of times on a full library —
/// and every one of those would otherwise be a system update to a Live Activity. ActivityKit
/// budgets those, so a scan that spends its allowance in the first ten seconds goes quiet for
/// the rest of the run, which is the opposite of what a live surface is for.
///
/// Anything a person would notice still goes through immediately: a change of phase, a change of
/// stage, and the end of the scan whatever the timing.
public struct LiveScanPublishPolicy: Sendable, Hashable {

    /// The floor between two updates that only move the bar along.
    public var minimumInterval: TimeInterval

    public init(minimumInterval: TimeInterval = 1.5) {
        self.minimumInterval = max(minimumInterval, 0)
    }

    public static let `default` = LiveScanPublishPolicy()

    public func shouldPublish(
        _ next: LiveScanState,
        after previous: LiveScanState?,
        publishedAt: Date?,
        now: Date
    ) -> Bool {
        guard let previous, let publishedAt else { return true }

        // An ended scan is the one update nobody may miss.
        if !next.isRunning { return true }
        if next.phase != previous.phase { return true }
        if next.stage != previous.stage { return true }

        guard now.timeIntervalSince(publishedAt) >= minimumInterval else { return false }

        // Past the interval, still nothing to say if the bar has not visibly moved.
        return percent(next) != percent(previous)
    }

    private func percent(_ state: LiveScanState) -> Int {
        Int((state.fraction * 100).rounded())
    }
}
