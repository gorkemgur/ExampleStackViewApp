import Foundation

/// A running scan, in the shape the Lock Screen and the Dynamic Island can render.
///
/// Everything a live surface shows is derived here rather than in the views, for two reasons:
/// the same state is drawn five different ways at five different sizes and they must never
/// disagree, and the Dynamic Island is the one place in the app that cannot be screenshotted in
/// CI — so its wording has to be testable without it.
public struct LiveScanState: Sendable, Hashable, Codable {

    public enum Phase: Int, Sendable, Hashable, Codable {
        case scanning
        case paused
        case finished
        case cancelled
        case failed
    }

    public let phase: Phase
    public let stage: ScanProgress.Stage
    public let completed: Int
    public let total: Int
    /// How many items the scan has decided it could remove so far.
    public let candidateCount: Int
    public let reclaimableBytes: Int64
    public let startedAt: Date

    public init(
        phase: Phase,
        stage: ScanProgress.Stage,
        completed: Int,
        total: Int,
        candidateCount: Int = 0,
        reclaimableBytes: Int64 = 0,
        startedAt: Date = Date()
    ) {
        self.phase = phase
        self.stage = stage
        self.total = max(total, 0)
        self.completed = min(max(completed, 0), self.total)
        self.candidateCount = max(candidateCount, 0)
        self.reclaimableBytes = max(reclaimableBytes, 0)
        self.startedAt = startedAt
    }

    /// A *finished* scan reads as complete however far the counter got: a bar that stops at
    /// 94% and then says "done" looks like something went wrong.
    ///
    /// That reasoning applies to finishing and to nothing else. It used to cover cancelled and
    /// failed too, so a scan you stopped at eighteen per cent drew a completely full bar, and
    /// one that crashed drew a completely full bar in the app's destructive red. A full track
    /// is the universal glyph for "done", and both of those are the opposite of done. Stopping
    /// where the work stopped is also the strongest signal on these surfaces that is not a
    /// colour: a silhouette you can read across a room.
    public var fraction: Double {
        guard phase != .finished else { return 1 }
        guard total > 0 else { return 0 }
        return min(Double(completed) / Double(total), 1)
    }

    public var isRunning: Bool { phase == .scanning || phase == .paused }

    public var isFinished: Bool { phase == .finished }

    public var foundSomething: Bool { candidateCount > 0 }

    /// What the surface leads with. Short on purpose — the Dynamic Island's expanded region
    /// gives this about a dozen characters before it truncates.
    public var headline: String {
        switch phase {
        case .scanning: return "Scanning"
        case .paused: return "Paused"
        case .finished: return foundSomething ? "Found space" : "All clean"
        case .cancelled: return "Stopped"
        case .failed: return "Scan failed"
        }
    }

    /// The line under the headline.
    public var detail: String {
        switch phase {
        case .scanning:
            return total > 0
                ? "\(stageLabel) · \(completed.formatted()) of \(total.formatted())"
                : stageLabel
        case .paused:
            return total > 0 ? "Held at \(completed.formatted()) of \(total.formatted())" : "Held"
        case .finished:
            guard foundSomething else { return "No duplicates worth removing" }
            return "\(ByteText.string(reclaimableBytes)) in \(Counting.items(candidateCount))"
        case .cancelled:
            return "Nothing was deleted"
        case .failed:
            return "Open DupeSpace to try again"
        }
    }

    /// Two or three glyphs: the compact trailing slot and the circular gauge label, neither of
    /// which is wide enough for "4.32 GB".
    ///
    /// Empty wherever the glyph in the neighbouring slot already carries the whole fact. Paused
    /// was already this way; cancelled and failed were an em dash, which is not information —
    /// a lone dash tinted grey beside a cross reads as a value that failed to load. Letting the
    /// pill shrink to its glyph is a silhouette change, which is a stronger signal at a glance
    /// than any character.
    ///
    /// The contract, which the surfaces have to keep: `compactValue` may be empty whenever the
    /// adjacent glyph says everything, and `displayValue` may never be empty on a surface that
    /// reserves a slot for it.
    public var compactValue: String {
        switch phase {
        case .scanning: return "\(Int((fraction * 100).rounded()))%"
        case .paused, .cancelled, .failed: return ""
        case .finished: return foundSomething ? ByteText.tight(reclaimableBytes) : ""
        }
    }

    /// The same value for a surface with room for it — the Lock Screen card and the expanded
    /// island, where "4.3 GB" fits and "4.3G" reads like a truncation.
    ///
    /// This used to fall through to `compactValue` for everything but `.finished`, so a paused
    /// scan gave the Lock Screen card an empty string for its hero figure and left the whole
    /// right-hand column a hole. Every phase answers here.
    public var displayValue: String {
        switch phase {
        case .scanning: return "\(Int((fraction * 100).rounded()))%"
        case .paused: return "Held"
        case .finished: return foundSomething ? ByteText.string(reclaimableBytes) : "All clean"
        case .cancelled: return "Stopped"
        case .failed: return "Failed"
        }
    }

    public var symbolName: String {
        switch phase {
        case .scanning: return "sparkle.magnifyingglass"
        case .paused: return "pause.circle"
        case .finished: return foundSomething ? "internaldrive.fill" : "checkmark.circle"
        case .cancelled: return "xmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    /// One word for the stage, for places that cannot fit the app's full sentence.
    public var stageLabel: String {
        switch stage {
        case .bucketing: return "Sorting"
        case .hashing: return "Reading"
        case .fingerprinting: return "Fingerprinting"
        case .sampling: return "Sampling video"
        case .matching: return "Matching"
        case .planning: return "Deciding"
        }
    }

    /// What a live surface should say it is doing, for VoiceOver and for the Dynamic Island's
    /// accessibility label, where the layout carries none of the meaning.
    public var accessibilityDescription: String {
        switch phase {
        case .scanning:
            return "Scanning for duplicates, \(compactValue) complete, \(stageLabel.lowercased())"
        case .paused:
            return "Scan paused at \(completed) of \(total)"
        case .finished:
            return foundSomething
                ? "Scan complete. \(ByteText.string(reclaimableBytes)) can be reclaimed."
                : "Scan complete. Nothing to clean up."
        case .cancelled:
            return "Scan stopped. Nothing was deleted."
        case .failed:
            return "Scan failed. Open DupeSpace to try again."
        }
    }

    /// What to show while a Live Activity is being prepared, and in previews.
    public static let preview = LiveScanState(
        phase: .scanning,
        stage: .fingerprinting,
        completed: 1_204,
        total: 5_000,
        candidateCount: 38,
        reclaimableBytes: 1_900_000_000,
        startedAt: Date(timeIntervalSince1970: 1_750_000_000)
    )
}
