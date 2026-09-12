import ActivityKit
import SwiftUI
import WidgetKit
import DupeCore

/// The scan as it happens: on the Lock Screen, and in the Dynamic Island.
///
/// A duplicate scan reads every original in the library, which on a full phone is minutes, not
/// seconds. Before this, the only way to know it was still going was to keep the app open — and
/// leaving the app is exactly what people do while they wait. This puts the same progress, and
/// the same running total of what is being found, where they are already looking.
struct ScanLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScanActivityAttributes.self) { context in
            ScanLockScreenView(state: context.state.scan, total: context.attributes.libraryItemCount)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let scan = context.state.scan

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(scan.headline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: scan.symbolName)
                            .foregroundStyle(ScanPalette.tint(for: scan))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .labelStyle(.titleAndIcon)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(scan.compactValue)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .foregroundStyle(ScanPalette.tint(for: scan))
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ScanProgressTrack(state: scan, height: 6)

                        HStack(spacing: 6) {
                            Text(scan.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Spacer(minLength: 0)

                            if scan.isRunning && scan.foundSomething {
                                RunningTotal(state: scan)
                            }
                        }
                    }
                    .animation(.smooth, value: scan)
                }
            } compactLeading: {
                Image(systemName: scan.symbolName)
                    .foregroundStyle(ScanPalette.tint(for: scan))
                    .symbolRenderingMode(.hierarchical)
            } compactTrailing: {
                Text(scan.compactValue)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .foregroundStyle(ScanPalette.tint(for: scan))
            } minimal: {
                // The minimal slot is a circle a few points across, so the ring carries the
                // progress and the glyph carries what kind of progress it is.
                ZStack {
                    Circle()
                        .stroke(ScanPalette.tint(for: scan).opacity(0.25), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(scan.fraction, 0.02))
                        .stroke(
                            ScanPalette.tint(for: scan),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: scan.symbolName)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ScanPalette.tint(for: scan))
                }
                .animation(.smooth, value: scan.fraction)
                .accessibilityLabel(scan.accessibilityDescription)
            }
            .widgetURL(URL(string: "dupespace://scan"))
            .keylineTint(ScanPalette.tint(for: scan))
        }
    }
}

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
                    Text(state.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Text(state.compactValue)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .foregroundStyle(ScanPalette.tint(for: state))
            }

            ScanProgressTrack(state: state, height: 8)

            HStack(spacing: 8) {
                if state.isRunning {
                    Text(state.startedAt, style: .timer)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: 52, alignment: .leading)
                }

                if state.foundSomething {
                    RunningTotal(state: state)
                } else if state.isRunning {
                    Text("Totals when it finishes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                if state.isRunning && total > 0 {
                    Text("\(total) to check")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .animation(.smooth, value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityDescription)
    }
}

/// The running total of what the scan has found. Deliberately the loudest thing on the surface
/// after the progress itself: it is the reason anyone started the scan.
private struct RunningTotal: View {

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
        .foregroundStyle(.green)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.green.opacity(0.15), in: Capsule())
    }
}

/// The progress bar. One implementation for every surface so a scan cannot look 40% done in the
/// island and 60% done on the Lock Screen.
private struct ScanProgressTrack: View {

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
        .animation(.smooth(duration: 0.4), value: state.fraction)
    }
}

enum ScanPalette {

    static func tint(for state: LiveScanState) -> Color {
        switch state.phase {
        case .scanning: return .cyan
        case .paused: return .orange
        case .finished: return state.foundSomething ? .green : .mint
        case .cancelled: return .secondary
        case .failed: return .red
        }
    }

    static func gradient(for state: LiveScanState) -> [Color] {
        switch state.phase {
        case .scanning: return [.cyan, .blue]
        case .paused: return [.orange, .yellow]
        case .finished: return state.foundSomething ? [.green, .mint] : [.mint, .teal]
        case .cancelled: return [.gray, .gray]
        case .failed: return [.red, .orange]
        }
    }
}
