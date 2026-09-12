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

        // The first thing the scan finds changes the card's layout — a whole row appears — and
        // that is exactly the "anything a person would notice" this type promises to let
        // through immediately.
        if next.foundSomething != previous.foundSomething { return true }

        guard now.timeIntervalSince(publishedAt) >= minimumInterval else { return false }

        // Past the interval, something has to have visibly moved.
        //
        // This used to be the percentage alone, which made the percentage the only value
        // capable of triggering a push — and then the surfaces made it the hero, because it
        // was the only number guaranteed to be current. The running total is the figure people
        // are actually waiting for; it gets to speak for itself.
        if percent(next) != percent(previous) { return true }
        return ByteText.compact(next.reclaimableBytes) != ByteText.compact(previous.reclaimableBytes)
    }

    private func percent(_ state: LiveScanState) -> Int {
        Int((state.fraction * 100).rounded())
    }
}
