import SwiftUI
import DupeCore

/// What the Lock Screen shows, and the same view the expanded island falls back on in spirit.
struct ScanLockScreenView: View {

    let state: LiveScanState
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(ScanPalette.tint(for: state).opacity(0.18))
                    Image(systemName: state.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ScanPalette.tint(for: state))
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.headline)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(state.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                Text(state.displayValue)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                    .foregroundStyle(ScanPalette.tint(for: state))
            }

            ScanProgressTrack(state: state, height: 8)

            HStack(spacing: 8) {
                if state.isRunning {
                    Text(state.startedAt, style: .timer)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }

                if state.isRunning && state.foundSomething {
                    RunningTotal(state: state)
                } else if state.isRunning {
                    Text("Totals when it finishes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if state.isRunning && total > 0 {
                    Text("\(total.formatted()) to check")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .animation(Motion.content, value: state.phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityDescription)
    }
}

/// The running total of what the scan has found. Deliberately the loudest thing on the surface
/// after the progress itself: it is the reason anyone started the scan.
struct RunningTotal: View {

    let state: LiveScanState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption2)
            Text(ByteText.compact(state.reclaimableBytes))
                .contentTransition(.numericText())
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(DS.brandBottom)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(DS.brandBottom.opacity(0.15), in: Capsule())
    }
}

/// The progress bar. One implementation for every surface so a scan cannot look 40% done in the
/// island and 60% done on the Lock Screen.
struct ScanProgressTrack: View {

    let state: LiveScanState
    var height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: ScanPalette.gradient(for: state),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    // Never quite zero: a bar with nothing in it looks like a scan that has not
                    // started, and by the time this is on screen it has.
                    .frame(width: max(proxy.size.width * state.fraction, height))
                    .opacity(state.phase == .paused ? 0.55 : 1)
            }
        }
        .frame(height: height)
        // `Motion.readout`, not `content`: this is pushed from a throttled Live Activity
        // update, and a 0.32s spring given a new value on every push never settles.
        .animation(Motion.readout, value: state.fraction)
    }
}

/// The live surfaces, in the app's own colours.
///
/// These were nine stock SwiftUI colours — cyan, blue, orange, yellow, green, mint, teal, red,
/// gray — on the two surfaces a person sees most often and least closely: a Lock Screen at
/// arm's length and a Dynamic Island the size of a thumbnail. Worse, `scanning` was
/// `[.cyan, .blue]`: the icon's gradient reversed and desaturated, so the activity under the
/// clock was a different blue-to-teal from the icon on the Home Screen above it.
///
/// Four states, four meanings, and each one already has a colour in this app.
enum ScanPalette {

    static func tint(for state: LiveScanState) -> Color {
        switch state.phase {
        case .scanning: return DS.brandBottom
        case .paused: return DS.tier(.burstLeftover)
        case .finished: return state.foundSomething ? DS.brandBottom : DS.onSlabAccent
        case .cancelled: return DS.neutral
        case .failed: return DS.destructive
        }
    }

    static func gradient(for state: LiveScanState) -> [Color] {
        switch state.phase {
        // The icon's own order, top stop first. Not reversed.
        case .scanning: return [DS.brandTop, DS.brandBottom]
        case .paused: return [DS.tier(.burstLeftover), DS.tier(.burstLeftover).opacity(0.7)]
        case .finished:
            return state.foundSomething
                ? [DS.brandTop, DS.brandBottom]
                : [DS.onSlabAccent, DS.brandBottom]
        case .cancelled: return [DS.neutral, DS.neutral]
        case .failed: return [DS.destructive, DS.destructive.opacity(0.7)]
        }
    }
}
