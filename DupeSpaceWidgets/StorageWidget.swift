import SwiftUI
import WidgetKit
import DupeCore

struct StorageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// True when the app has never written anything, so the numbers are illustrative.
    let isPlaceholder: Bool
}

struct StorageProvider: TimelineProvider {

    func placeholder(in context: Context) -> StorageEntry {
        StorageEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StorageEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        // Storage does not move on its own, and the app reloads this widget whenever it learns
        // something new. The hourly entry is only a floor, so a widget that missed a reload
        // still catches up rather than showing yesterday's number forever.
        let timeline = Timeline(
            entries: [currentEntry()],
            policy: .after(Date().addingTimeInterval(60 * 60))
        )
        completion(timeline)
    }

    private func currentEntry() -> StorageEntry {
        guard let stored = SharedContainer.snapshotStore()?.read() else {
            return StorageEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
        }
        return StorageEntry(date: Date(), snapshot: stored, isPlaceholder: false)
    }
}

struct StorageWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DupeSpaceStorage", provider: StorageProvider()) { entry in
            StorageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DeepLink.scan.url)
        }
        .configurationDisplayName("Space")
        .description("What your storage looks like, and what the last scan found you could remove.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct StorageWidgetView: View {

    @Environment(\.widgetFamily) private var family

    let entry: StorageEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text("\(ByteText.compact(entry.snapshot.availableCapacity)) free")
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: - Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(ByteText.compact(entry.snapshot.availableCapacity))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("free")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            CapacityTrack(snapshot: entry.snapshot, height: 8)
                .padding(.top, 8)

            Spacer(minLength: 6)

            reclaimable
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(ByteText.compact(entry.snapshot.availableCapacity))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("free")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("of \(ByteText.compact(entry.snapshot.totalCapacity))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                CapacityTrack(snapshot: entry.snapshot, height: 10)
                    .padding(.top, 10)

                Spacer(minLength: 4)

                legend
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                reclaimable

                if entry.snapshot.duplicateCount > 0 {
                    Text(entry.snapshot.duplicateCount == 1 ? "1 copy" : "\(entry.snapshot.duplicateCount) copies")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let scanned = entry.snapshot.lastScanAt {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Last scan")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Text(scanned, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Lock Screen

    private var circular: some View {
        Gauge(value: min(entry.snapshot.usedFraction, 1)) {
            Image(systemName: "internaldrive")
        } currentValueLabel: {
            Text(ByteText.tight(entry.snapshot.availableCapacity))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(ByteText.compact(entry.snapshot.availableCapacity)) free")
                .font(.headline)
                .widgetAccentable()

            if entry.snapshot.reclaimableBytes > 0 {
                Text("\(ByteText.compact(entry.snapshot.reclaimableBytes)) to reclaim")
                    .font(.caption)
            } else {
                Text("Nothing found to remove")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Gauge(value: min(entry.snapshot.usedFraction, 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var reclaimable: some View {
        if entry.snapshot.reclaimableBytes > 0 {
            VStack(alignment: .leading, spacing: 1) {
                Text(ByteText.compact(entry.snapshot.reclaimableBytes))
                    .font(.headline)
                    .foregroundStyle(DS.deep)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(entry.snapshot.losslessBytes > 0 ? "to reclaim, no loss" : "to reclaim")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else if entry.snapshot.hasScanned {
            Text("Nothing to clean up")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Open to scan")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendDot(color: DS.deep, title: "Photos")
            legendDot(color: DS.neutral, title: "Other")
            legendDot(color: DS.well, title: "Free")
        }
    }

    private func legendDot(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// The same proportional bar the app shows, at widget scale.
///
/// Literally the same one now. This used to be a second implementation — its own widths, its
/// own 1.5pt gaps, `.accentColor` and two greys — drawing the identical measurement in a
/// different shape and different colours from the app's, because `MeterTrack` lived in the app
/// target and the extension could not see it. The design system moved to `Shared/`; this is a
/// call site.
struct CapacityTrack: View {

    let snapshot: WidgetSnapshot
    var height: CGFloat = 8

    var body: some View {
        MeterTrack(
            segments: [
                MeterTrack.Segment(
                    id: "library",
                    value: Double(min(snapshot.libraryBytes, snapshot.usedCapacity)),
                    color: DS.deep
                ),
                MeterTrack.Segment(id: "other", value: Double(otherBytes), color: DS.neutral)
            ],
            total: Double(max(snapshot.totalCapacity, 1)),
            height: height,
            motion: nil
        )
    }

    private var otherBytes: Int64 {
        max(snapshot.usedCapacity - snapshot.libraryBytes, 0)
    }
}
