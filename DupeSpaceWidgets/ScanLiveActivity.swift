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
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
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
                    .animation(Motion.content, value: scan.phase)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
                }
                .animation(Motion.content, value: scan.fraction)
                .accessibilityLabel(scan.accessibilityDescription)
            }
            .widgetURL(URL(string: "dupespace://scan"))
            .keylineTint(ScanPalette.tint(for: scan))
        }
    }
}
