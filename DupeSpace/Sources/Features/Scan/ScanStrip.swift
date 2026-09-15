import SwiftUI
import DupeCore

/// What a running scan looks like from any screen that is not the scan screen.
///
/// The scan outlives the screen that started it — that is the whole of the previous phase — and
/// the moment it did, it became possible to have a forty-minute job running with nothing on
/// screen to say so. The Lock Screen knew, through the Live Activity, and the app itself did
/// not.
///
/// The decision lives here rather than inside the view so it can be tested without a renderer:
/// what has to be right is *when* the strip appears and whether its reading agrees with the
/// scan screen's, and neither of those is a drawing question.
struct ScanStripState: Equatable {

    /// The stage, in `ScanCopy`'s words rather than a second set of its own.
    let title: String
    /// Rounded the way `ScanView`'s progress card rounds it. Truncating instead would leave the
    /// strip a point behind the card it links to, and there would be no way to tell which of
    /// the two was wrong.
    let percent: Int
    let fraction: Double
    let isPaused: Bool

    /// The hold is drawn as a tint and a glyph. Neither reaches VoiceOver, so it is said.
    var accessibilityLabel: String { isPaused ? "Scan paused" : "Scan in progress" }
    var accessibilityValue: String { "\(title), \(percent) percent" }
}

enum ScanStrip {

    /// `nil` means draw nothing — and drawing nothing is the common case, so the strip may only
    /// take the top inset off every screen in the app when there is genuinely a scan to report.
    static func state(
        isScanning: Bool,
        isPaused: Bool,
        progress: ScanProgress?,
        isShowingScan: Bool
    ) -> ScanStripState? {
        // The scan screen already draws this reading, larger and with controls beside it. A
        // second copy of it directly above reads as a rendering fault.
        guard isScanning, !isShowingScan else { return nil }

        // A scan that has started but not yet reported still shows its first stage. The gap is
        // short, and an empty strip that appears a beat later is a flicker.
        let stage = progress?.stage ?? .bucketing
        let fraction = progress?.fraction ?? 0

        return ScanStripState(
            title: ScanCopy.title(for: stage),
            percent: Int((fraction * 100).rounded()),
            fraction: fraction,
            isPaused: isPaused
        )
    }
}

/// The strip itself: one line of words, one reading, and a track under both.
///
/// Sized as small as it can be and still be a touch target, because it is subtracted from every
/// other screen's height for as long as the scan runs.
struct ScanStripView: View {

    let state: ScanStripState?
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A `Group` rather than a bare `if`: the animation has to be attached to something that
        // is in the hierarchy whether or not there is a scan, or the strip's arrival and
        // departure are not animated at all — they are the two moments it moves every other
        // screen in the app up or down.
        Group {
            if let state {
                strip(state)
            }
        }
        .animation(reduceMotion ? nil : Motion.content, value: state)
    }

    private func strip(_ state: ScanStripState) -> some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: state.isPaused ? "pause.fill" : "magnifyingglass")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint(state))

                    Text(state.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.onSlab)
                        // One line, shrinking rather than wrapping: a strip that grows to
                        // two lines moves every screen below it down mid-scan.
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    Text("\(state.percent)%")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tint(state))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.neutralOnSlab)
                }

                // The same track the progress card and the disk gauge use, so a measurement
                // looks like a measurement everywhere in this app. `Motion.readout`, not
                // `Motion.content`: this value changes several times a second.
                MeterTrack(
                    segments: [
                        MeterTrack.Segment(id: "scan", value: state.fraction, color: tint(state))
                    ],
                    total: 1,
                    height: 3,
                    motion: reduceMotion ? nil : Motion.readout
                )
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(DS.slab)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.hairline)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
        .accessibilityHint("Opens the scan")
        .accessibilityIdentifier("scan.strip")
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func tint(_ state: ScanStripState) -> Color {
        // The same amber the progress card uses for a hold, so the two never disagree about
        // what colour "paused" is.
        state.isPaused ? DS.tier(.burstLeftover) : DS.deep
    }
}
