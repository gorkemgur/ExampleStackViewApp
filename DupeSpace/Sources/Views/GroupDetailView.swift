import SwiftUI
import DupeCore

/// One group, opened up: the copy that stays, then every copy on offer with the evidence for
/// each one directly underneath it.
struct GroupDetailView: View {

    /// Looked up from the model on every pass, never held.
    ///
    /// This used to be `let group: ReviewGroup` — a value frozen when the link was pushed. Tap
    /// "Keep this one instead" and the model rebuilds its sections correctly, but this screen
    /// went on showing the *old* survivor under the words "Staying — your choice, not the
    /// app's", with rows for members that had just stopped being offered and a "Select all"
    /// built from stale ids. Ticking any of them made `canDelete` false and the red key dead,
    /// with nothing anywhere saying why. The validator did its job; the screen was lying to the
    /// person using it while they made further decisions on it.
    let reviewGroupID: String
    @ObservedObject var model: ReviewViewModel
    let loader: any ThumbnailLoading

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingClearAll = false

    init(group: ReviewGroup, model: ReviewViewModel, loader: any ThumbnailLoading) {
        self.reviewGroupID = group.id
        self.model = model
        self.loader = loader
    }

    private var group: ReviewGroup? {
        model.sections.lazy.flatMap(\.groups).first { $0.id == reviewGroupID }
    }

    /// The engine's id for this group. A review group is one tier's slice of it, so its own id
    /// carries the tier as well.
    private var groupID: String? { group?.candidates.first?.groupID }

    private var tint: Color { DS.tier(group?.tier ?? .identical) }

    var body: some View {
        Group {
            if let group {
                content(group)
            } else {
                // Everything in it has been deleted, or the group stopped existing when the
                // survivor changed. Standing on a screen about a group that is gone is not a
                // state; going back is.
                ContentUnavailableView(
                    "This group is gone",
                    systemImage: "checkmark.seal",
                    description: Text("Every copy here has been dealt with.")
                )
                .background(DS.ink, ignoresSafeAreaEdges: .all)
                .accessibilityIdentifier("group.gone")
                .task { dismiss() }
            }
        }
    }

    private func content(_ group: ReviewGroup) -> some View {
        ScrollView {
            // Lazy: a burst can leave sixty copies in one group, and every row here carries a
            // thumbnail that requests itself on appear.
            LazyVStack(spacing: 16) {
                keeperPanel(group)

                // A group can hold sixty copies of a burst. Without this the only way to tick
                // a subset was sixty taps, or ticking the whole group on the row before and
                // untapping back down.
                copiesHeader(group)

                ForEach(group.items) { item in
                    candidatePanel(item, in: group)
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

    private func selectedCount(_ group: ReviewGroup) -> Int {
        group.candidates.reduce(0) { model.selection.isSelected($1.id) ? $0 + 1 : $0 }
    }

    /// How many copies are on offer here, and one control for all of them.
    ///
    /// It can never tick the survivor: `candidateIDs` excludes it by construction, and the
    /// only thing in this app allowed to leave a group with nothing is the deliberately
    /// awkward control at the bottom of this screen.
    private func copiesHeader(_ group: ReviewGroup) -> some View {
        let selectedCount = selectedCount(group)
        return HStack(spacing: DS.Space.s) {
            Text(Counting.copies(group.candidates.count))
                .font(.subheadline.weight(.semibold))

            Text("\(selectedCount) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer(minLength: 8)

            Button {
                withAnimation(Motion.control) {
                    model.setSelected(selectedCount < group.candidates.count, in: group)
                }
            } label: {
                Text(selectedCount < group.candidates.count ? "Select all" : "Deselect all")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("group.selectall")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The survivor

    private func keeperPanel(_ group: ReviewGroup) -> some View {
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

            Text(keeperFooter(group))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func keeperFooter(_ group: ReviewGroup) -> String {
        guard let groupID, model.overrides[groupID]?.keeperID != nil else {
            return "Every copy below was compared against this one directly. It is never offered for deletion — unless you say otherwise."
        }
        return "Your choice, not the app's. Every copy below was compared against this one directly."
    }

    // MARK: - One copy on offer

    private func candidatePanel(_ item: MediaItem, in group: ReviewGroup) -> some View {
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
