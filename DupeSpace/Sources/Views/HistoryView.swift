import SwiftUI
import DupeCore

/// The receipt.
///
/// Most cleaners forget what they did the moment they do it. Keeping the record is what makes
/// an irreversible-feeling action feel survivable: you can see exactly what went, what stayed
/// in its place, and how long you still have to change your mind.
struct HistoryView: View {

    @EnvironmentObject private var history: HistoryViewModel
    @State private var expanded: Set<String> = []
    @State private var confirmingClear = false

    /// Pushed from the overview rather than owning a tab, so it has no navigation stack of its
    /// own: it inherits the one it was pushed onto.
    var body: some View {
        Group {
            if history.isEmpty {
                ContentUnavailableView {
                    Label("Nothing yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Once you scan or delete, what happened shows up here — including what was kept in place of each copy you removed.")
                        .accessibilityIdentifier("history.empty")
                }
            } else {
                timeline
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .background(DS.ink, ignoresSafeAreaEdges: .all)
        .toolbar {
            if !history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) {
                        confirmingClear = true
                    }
                    .tint(DS.deep)
                    .accessibilityIdentifier("history.clear")
                }
            }
        }
        .confirmationDialog(
            "Clear the history?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear the record", role: .destructive) {
                withAnimation(Motion.content) { history.clear() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This only forgets the record. Nothing that was deleted comes back, and nothing that is still in Recently Deleted is affected.")
        }
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                lifetimeCard

                if let recoverable = history.recoverableDeletions().first {
                    recoveryCard(recoverable)
                }

                ForEach(history.timeline) { entry in
                    entryCard(entry)
                        .cardEntrance()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .animation(Motion.content, value: expanded)
            .animation(Motion.content, value: history.timeline.count)
        }
    }

    // MARK: - Cards

    /// The lifetime total, set like the disk reading on the overview and sitting straight on the
    /// page for the same reason: it is the headline of the screen, not one section of it.
    private var lifetimeCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow("Reclaimed with DupeSpace", tint: DS.deep)

            Readout.bytes(history.totalReclaimedBytes, tint: DS.deep)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .accessibilityIdentifier("history.total")

            Text("across \(Counting.items(history.totalItemsDeleted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    private func recoveryCard(_ record: DeletionRecord) -> some View {
        Card(rail: DS.tier(.burstLeftover)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.title3)
                    .foregroundStyle(DS.tier(.burstLeftover))

                VStack(alignment: .leading, spacing: 4) {
                    Text("You can still change your mind")
                        .font(.subheadline.weight(.semibold))
                    Text("Your most recent deletion is \(HistoryCopy.recoveryWindow(record) ?? "recoverable") in Photos › Recently Deleted. Emptying that album is also what actually frees the space.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private func entryCard(_ entry: HistoryEntry) -> some View {
        switch entry {
        case let .scan(record):
            scanCard(record)
        case let .deletion(record):
            deletionCard(record, entryID: entry.id)
        }
    }

    private func scanCard(_ record: ScanRecord) -> some View {
        Card(rail: DS.deep) {
            HStack(alignment: .top, spacing: 12) {
                badge(symbol: "magnifyingglass", tint: DS.deep)

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        record.foundSomething
                            ? "Found \(ByteFormatting.string(record.reclaimableBytes)) worth removing"
                            : "Nothing to clean up"
                    )
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("history.scan.headline")

                    Text("\(Counting.items(record.itemsScanned)) scanned in \(HistoryCopy.duration(record.duration)) · \(HistoryCopy.when(record.finishedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if record.cloudOnlyCount > 0 {
                        Text("\(Counting.items(record.cloudOnlyCount)) left in iCloud, unread")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func deletionCard(_ record: DeletionRecord, entryID: String) -> some View {
        Card(rail: DS.deep) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(Motion.content) {
                        if expanded.contains(entryID) {
                            expanded.remove(entryID)
                        } else {
                            expanded.insert(entryID)
                        }
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        badge(symbol: "trash", tint: DS.deep)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Removed \(Counting.items(record.itemCount)) · \(ByteFormatting.string(record.reclaimedBytes))")
                                .font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("history.deletion.headline")

                            Text(HistoryCopy.when(record.performedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let window = HistoryCopy.recoveryWindow(record) {
                                // Orange text on a white card measured barely 2:1. The colour
                                // moves to the glyph and the tinted capsule; the words, which
                                // are the part that has to be read, go back to full contrast.
                                Label(window, systemImage: "clock.arrow.circlepath")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        DS.tier(.burstLeftover).opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    )
                            }
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded.contains(entryID) ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded.contains(entryID) {
                    VStack(spacing: 0) {
                        ForEach(record.items) { item in
                            itemRow(item)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func itemRow(_ item: DeletedItemRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider()
                .padding(.bottom, 7)

            HStack(spacing: 8) {
                Image(systemName: item.kind == .video ? "film" : "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(item.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(ByteFormatting.string(item.bytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text("kept \(item.keptInsteadName) instead · \(ScanCopy.title(for: item.tier).lowercased())")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.bottom, 7)
    }

    private func badge(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.14))
            )
    }
}
