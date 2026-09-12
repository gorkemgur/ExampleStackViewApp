import SwiftUI
import DupeCore

/// One group, opened up: the copy that stays, then every copy on offer with the evidence for
/// each one directly underneath it.
struct GroupDetailView: View {

    let group: ReviewGroup
    @ObservedObject var model: ReviewViewModel
    let loader: any ThumbnailLoading

    @State private var confirmingClearAll = false

    /// The engine's id for this group. A review group is one tier's slice of it, so its own id
    /// carries the tier as well.
    private var groupID: String? { group.candidates.first?.groupID }

    private var tint: Color { DS.tier(group.tier) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                keeperPanel

                ForEach(group.items) { item in
                    candidatePanel(item)
                }

                if let groupID {
                    droppedNotice(groupID)
                    clearEverythingSection(groupID)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(DS.ink, ignoresSafeAreaEdges: .all)
        .sensoryFeedback(.selection, trigger: model.selection.count)
        .navigationTitle(ScanCopy.title(for: group.tier))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The survivor

    private var keeperPanel: some View {
        Card("Staying", symbolName: "checkmark.seal.fill", identifier: "group.keeper", rail: DS.tier(.inferiorCopy)) {
            HStack(spacing: 12) {
                ThumbnailView(item: group.keeper, side: 64, loader: loader)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.keeper.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(group.keeper.pixelWidth)×\(group.keeper.pixelHeight) · \(ByteFormatting.string(group.keeper.totalByteSize))")
                        .font(.system(.caption, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Text(keeperFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keeperFooter: String {
        guard let groupID, model.overrides[groupID]?.keeperID != nil else {
            return "Every copy below was compared against this one directly. It is never offered for deletion — unless you say otherwise."
        }
        return "Your choice, not the app's. Every copy below was compared against this one directly."
    }

    // MARK: - One copy on offer

    private func candidatePanel(_ item: MediaItem) -> some View {
        Card(rail: tint) {
            candidateRow(item)

            CompareSliderView(keeper: group.keeper, candidate: item, loader: loader)

            ComparisonHighlights(keeper: group.keeper, candidate: item)

            DisclosureGroup {
                ComparisonTable(keeper: group.keeper, candidate: item)
            } label: {
                Text("Every measurement")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.deep)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .tint(DS.deep)
            .accessibilityIdentifier("candidate.table.\(item.id)")

            keepInsteadButton(item)
        }
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
            }
            .buttonStyle(.keyQuiet)
            .accessibilityIdentifier("candidate.keep.\(item.id)")
        }
    }

    /// Says plainly what changing the survivor cost, rather than letting copies vanish from the
    /// list without explanation.
    @ViewBuilder
    private func droppedNotice(_ groupID: String) -> some View {
        let dropped = model.droppedMembers(inGroup: groupID)
        if !dropped.isEmpty {
            Card("No longer offered", symbolName: "eye.slash", identifier: "group.dropped.title") {
                Text("\(Counting.items(dropped.count)) from this group \(dropped.count == 1 ? "is" : "are") no longer offered. They were each compared with the copy the app had chosen, and with nothing else — so against the one you kept, there is no evidence. Scan again to compare them directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("group.dropped")
            }
        }
    }

    @ViewBuilder
    private func clearEverythingSection(_ groupID: String) -> some View {
        // The one card in the app that carries the destructive colour without destroying
        // anything: it arms the choice, and the red key that acts on it is still two screens
        // away. The rail says what this is about; the fill does not pretend to be the act.
        Card(rail: DS.destructive) {
            if model.isClearingEverything(inGroup: groupID) {
                Label("Every copy in this group is selected, including the one that was staying.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DS.tier(.burstLeftover))
                    .fixedSize(horizontal: false, vertical: true)

                Button("Keep one after all", role: .cancel) {
                    model.setClearingEverything(false, inGroup: groupID)
                }
                .buttonStyle(.keyQuiet)
                .accessibilityIdentifier("group.keepone")
            } else {
                Button(role: .destructive) {
                    confirmingClearAll = true
                } label: {
                    Label("Delete every copy in this group", systemImage: "trash")
                }
                .buttonStyle(KeyButtonStyle(fill: AnyShapeStyle(DS.well), foreground: DS.destructive))
                .accessibilityIdentifier("group.deleteall")
            }

            Text("The app will never select the last copy of anything on its own. This is the one way to say you want none of them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                TickBox(state: model.selection.isSelected(item.id) ? .full : .empty, tint: tint)

                ThumbnailView(item: item, side: 52, loader: loader)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ByteFormatting.string(item.totalByteSize))
                        .font(.system(.caption, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The tick is drawn shapes, so it says nothing on its own — and this button never had
        // a label either. Without both, the row announced a filename and a size with no
        // indication of whether it was selected, on the screen where selection is the decision.
        .accessibilityLabel(item.displayName)
        .accessibilityValue(model.selection.isSelected(item.id) ? "Selected for deletion" : "Not selected")
        .accessibilityAddTraits(model.selection.isSelected(item.id) ? [.isSelected] : [])
        .accessibilityHint("Double tap to change whether this copy is deleted")
        .accessibilityIdentifier("candidate.\(item.id)")
    }
}
