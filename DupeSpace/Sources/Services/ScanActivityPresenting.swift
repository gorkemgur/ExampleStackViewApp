import ActivityKit
import Foundation
import DupeCore

/// Whatever drives the live scan surfaces.
///
/// A protocol because ActivityKit will not start an activity outside a real, foregrounded app —
/// so the tests watch what the scan publishes through a stub instead, and the real one stays
/// thin enough to read.
@MainActor
protocol ScanActivityPresenting: AnyObject {
    func start(libraryItemCount: Int, state: LiveScanState)
    func update(_ state: LiveScanState)
    func finish(_ state: LiveScanState)
    /// Clears anything left behind by a previous run of the app.
    func clearOrphans()
}

extension ScanActivityPresenting {
    func clearOrphans() {}
}

/// The Lock Screen and Dynamic Island presentation of a running scan.
@MainActor
final class LiveScanActivityController: ScanActivityPresenting {

    private let policy: LiveScanPublishPolicy
    private let clock: () -> Date

    private var activity: Activity<ScanActivityAttributes>?
    private var lastPublished: LiveScanState?
    private var lastPublishedAt: Date?

    /// Nonisolated so a SwiftUI view's initialiser can build one without hopping actors; it
    /// only sets stored properties, and everything that touches ActivityKit is isolated.
    nonisolated init(
        policy: LiveScanPublishPolicy = .default,
        clock: @escaping () -> Date = Date.init
    ) {
        self.policy = policy
        self.clock = clock
    }

    /// False on iPad and Mac, and whenever the user has turned Live Activities off for the app.
    /// Everything here is best-effort for that reason: the scan itself must never depend on it.
    private var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(libraryItemCount: Int, state: LiveScanState) {
        guard isAvailable, activity == nil else { return }

        do {
            activity = try Activity.request(
                attributes: ScanActivityAttributes(libraryItemCount: libraryItemCount),
                // A stale date from the first moment. The app is suspended the instant it goes
                // to the background, so a scan that is never returned to stops being updated
                // with no chance to say so; the system then dims the activity rather than
                // presenting a frozen percentage as live.
                content: ActivityContent(state: .init(state), staleDate: staleDate(from: clock())),
                pushType: nil
            )
            lastPublished = state
            lastPublishedAt = clock()
        } catch {
            // A refused activity is not a failed scan. Nothing else in the app changes.
            activity = nil
        }
    }

    func update(_ state: LiveScanState) {
        guard let activity else { return }

        let now = clock()
        guard
            policy.shouldPublish(state, after: lastPublished, publishedAt: lastPublishedAt, now: now)
        else { return }

        lastPublished = state
        lastPublishedAt = now

        Task {
            await activity.update(
                ActivityContent(state: .init(state), staleDate: staleDate(from: now))
            )
        }
    }

    /// How long a figure on the Lock Screen may be presented as current before the system
    /// should treat it as out of date.
    private func staleDate(from now: Date) -> Date {
        now.addingTimeInterval(5 * 60)
    }

    /// Ends any activity left over from a previous launch.
    ///
    /// If the app is force-quit mid-scan, its Live Activity survives the process that owned it
    /// and sits on the Lock Screen reporting a scan that is no longer running. Nothing else
    /// will ever clear it, so the next launch does.
    func clearOrphans() {
        for orphan in Activity<ScanActivityAttributes>.activities where orphan.id != activity?.id {
            let last = orphan.content.state.scan
            let stopped = LiveScanState(
                phase: .cancelled,
                stage: last.stage,
                completed: last.completed,
                total: last.total,
                startedAt: last.startedAt
            )
            Task {
                await orphan.end(
                    ActivityContent(state: .init(stopped), staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }

    func finish(_ state: LiveScanState) {
        guard let activity else { return }

        self.activity = nil
        lastPublished = nil
        lastPublishedAt = nil

        // Left on screen for a moment rather than vanishing: the last thing it says is how much
        // space the scan found, which is the whole reason it was started.
        Task {
            await activity.end(
                ActivityContent(state: .init(state), staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(8))
            )
        }
    }
}
