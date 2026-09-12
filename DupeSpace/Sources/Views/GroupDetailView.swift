import SwiftUI
import DupeCore

struct GroupDetailView: View {

    let group: ReviewGroup
    @ObservedObject var model: ReviewViewModel
    let loader: any ThumbnailLoading

    @State private var confirmingClearAll = false

    /// The engine's id for this group. A review group is one tier's slice of it, so its own id
    /// carries the tier as well.
    private var groupID: String? { group.candidates.first?.groupID }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    ThumbnailView(item: group.keeper, side: 72, loader: loader)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.keeper.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(group.keeper.pixelWidth)×\(group.keeper.pixelHeight) · \(ByteFormatting.string(group.keeper.totalByteSize))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Staying")
            } footer: {
                Text(keeperFooter)
            }

            ForEach(group.items) { item in
                Section {
                    candidateRow(item)
                    ComparisonTable(keeper: group.keeper, candidate: item)
                    keepInsteadButton(item)
                }
            }

            if let groupID {
                droppedNotice(groupID)
                clearEverythingSection(groupID)
            }
        }
        .sensoryFeedback(.selection, trigger: model.selection.count)
        .navigationTitle(ScanCopy.title(for: group.tier))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var keeperFooter: String {
        guard let groupID, model.overrides[groupID]?.keeperID != nil else {
            return "Every copy below was compared against this one directly. It is never offered for deletion — unless you say otherwise."
        }
        return "Your choice, not the app's. Every copy below was compared against this one directly."
    }

    /// The other half of "your call": the app's pick is a default, and defaults can be wrong
    /// about someone else's photographs.
    @ViewBuilder
    private func keepInsteadButton(_ item: MediaItem) -> some View {
        if let groupID {
            Button {
                model.chooseKeeper(item.id, inGroup: groupID)
            } label: {
                Label("Keep this one instead", systemImage: "arrow.triangle.swap")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("candidate.keep.\(item.id)")
        }
    }

    /// Says plainly what changing the survivor cost, rather than letting copies vanish from the
    /// list without explanation.
    @ViewBuilder
    private func droppedNotice(_ groupID: String) -> some View {
        let dropped = model.droppedMembers(inGroup: groupID)
        if !dropped.isEmpty {
            Section {
                Text("\(Counting.items(dropped.count)) from this group \(dropped.count == 1 ? "is" : "are") no longer offered. They were each compared with the copy the app had chosen, and with nothing else — so against the one you kept, there is no evidence. Scan again to compare them directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("group.dropped")
            }
        }
    }

    @ViewBuilder
    private func clearEverythingSection(_ groupID: String) -> some View {
        Section {
            if model.isClearingEverything(inGroup: groupID) {
                Label("Every copy in this group is selected, including the one that was staying.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Button("Keep one after all", role: .cancel) {
                    model.setClearingEverything(false, inGroup: groupID)
                }
                .accessibilityIdentifier("group.keepone")
            } else {
                Button(role: .destructive) {
                    confirmingClearAll = true
                } label: {
                    Label("Delete every copy in this group", systemImage: "trash")
                }
                .accessibilityIdentifier("group.deleteall")
            }
        } footer: {
            Text("The app will never select the last copy of anything on its own. This is the one way to say you want none of them.")
        }
        .confirmationDialog(
            "Delete every copy, keeping none?",
            isPresented: $confirmingClearAll,
            titleVisibility: .visible
        ) {
            Button("Select them all", role: .destructive) {
                model.setClearingEverything(true, inGroup: groupID)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This selects the survivor as well. Nothing is deleted until you confirm on the previous screen.")
        }
    }

    @ViewBuilder
    private func candidateRow(_ item: MediaItem) -> some View {
        Button {
            withAnimation(Motion.control) {
                model.toggle(item.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: model.selection.isSelected(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(model.selection.isSelected(item.id) ? Color.accentColor : Color.secondary)
                    .symbolEffect(.bounce, value: model.selection.isSelected(item.id))

                ThumbnailView(item: item, side: 56, loader: loader)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ByteFormatting.string(item.totalByteSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("candidate.\(item.id)")
    }
}
