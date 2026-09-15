import SwiftUI
import UniformTypeIdentifiers
import DupeCore

/// The last screen before anything is destroyed.
///
/// It leads with what the user will actually get back and when, because "frees 12 GB" is a
/// lie if most of that sits in Recently Deleted for thirty days or belongs to originals that
/// were never on the device in the first place.
struct ConfirmDeleteSheet: View {

    @ObservedObject var model: ReviewViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pickingFolder = false

    /// Counts frozen the moment the key is spent. The selection is cleared the instant the
    /// deletion succeeds, so reading it afterwards would collapse the instrument to nothing at
    /// the exact frame it is meant to show the arrival.
    @State private var staged: (files: Int, photos: Int, savings: SavingsBreakdown)?

    var body: some View {
        content
            // Sized to what it holds: at full height the sheet left 400pt of empty grey
            // between the breakdown and the button that matters.
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headline

                    // Everything below is about a decision that has already been taken. Leaving
                    // it up while the sheet waits to dismiss is what produced the worst frame in
                    // the recording: the ledger, the export offer and a dead "Delete 0 items"
                    // key, all describing a selection that had just been cleared.
                    if model.outcome == nil {
                        breakdown

                        if model.judgementCallCount > 0 {
                            judgementWarning
                        }

                        keepACopy
                    }

                    if let failure = model.failure {
                        Card(
                            "Nothing was deleted",
                            symbolName: "exclamationmark.triangle",
                            identifier: "confirm.failure",
                            rail: DS.neutral
                        ) {
                            Text(failure)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 20)
                .animation(Motion.content, value: model.judgementCallCount)
                .animation(Motion.content, value: model.failure)
                .animation(Motion.content, value: model.exportReceipt)
                .animation(Motion.content, value: model.isExporting)
            }
            .background(DS.ink, ignoresSafeAreaEdges: .all)
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("confirm.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                deleteKey
            }
        }
    }

    // MARK: - Keeping the originals

    /// The promise the concept document has made since day one, and the one thing in it that
    /// had no code behind it: before anything is destroyed, the original bytes can be written
    /// to a folder the user chooses, with a manifest beside them saying what each file was and
    /// which copy it was being deleted in favour of.
    ///
    /// Offered, never forced. Recently Deleted already covers photos for thirty days, and
    /// making someone pick a folder before they can tidy up their library would be the app
    /// deciding how careful they have to be. Files in a granted folder have no thirty days at
    /// all, so the copy says so when the selection contains any.
    @ViewBuilder
    private var keepACopy: some View {
        Card(
            "Keep the originals first",
            symbolName: "square.and.arrow.down",
            identifier: "confirm.export.title",
            rail: DS.deep
        ) {
            if let receipt = model.exportReceipt {
                Label {
                    Text("\(Counting.items(receipt.exportedCount)) written to \(receipt.folderName)")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.deep)
                }
                .font(.footnote)
                .accessibilityIdentifier("confirm.export.done")

                Text("The folder holds the original bytes and a manifest.json naming, for each one, the copy that stays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.exportCoversSelection {
                    // Silence here would be the dangerous kind: a green tick above a red key,
                    // covering a selection it no longer describes.
                    Text("The selection has changed since then, so the export no longer covers all of it.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.tier(.burstLeftover))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("confirm.export.stale")
                }

                if receipt.failedCount > 0 {
                    Text("\(Counting.items(receipt.failedCount)) could not be written — the originals are in iCloud rather than on this device, and nothing was downloaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("confirm.export.failed")
                }
            } else {
                Text(exportPitch)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    pickingFolder = true
                } label: {
                    if model.isExporting {
                        ProgressView().tint(DS.deep)
                    } else {
                        Label("Choose a folder", systemImage: "folder.badge.plus")
                    }
                }
                .buttonStyle(.keyQuiet)
                .disabled(model.isExporting || !model.canDelete)
                .accessibilityIdentifier("confirm.export")
            }

            if let failure = model.exportFailure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("confirm.export.failure")
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { outcome in
            guard case let .success(url) = outcome else { return }
            Task { await model.exportOriginals(to: url) }
        }
    }

    private var exportPitch: String {
        let immediate = model.savings.immediateBytes > 0
        let base = "Write the original bytes of \(Counting.items(model.selection.count)) to a folder you pick, with a manifest saying what each one was and which copy stays."
        guard immediate else {
            return base + " Optional — photos also go to Recently Deleted for 30 days."
        }
        return base + " Some of this selection lives outside the photo library, where deletion is immediate and there is no Recently Deleted to fall back on."
    }

    /// The one place in the app that is red. Everything before this point is reversible; this
    /// button is not, so it is the only control that gets the colour of a thing you cannot undo.
    ///
    /// It is spent, not transformed. A `matchedGeometryEffect` morph from the key into the
    /// instrument was tempting and is wrong: `DS.destructive` belongs to the irreversible
    /// *control*, and carrying red into the *process* would make the running deletion look like
    /// something still tappable.
    @ViewBuilder
    private var deleteKey: some View {
        VStack(spacing: 0) {
            if (model.isDeleting || model.outcome != nil), let staged {
                handover(staged)
                    .transition(.opacity)
            } else {
                Button(role: .destructive) {
                    // Frozen before the work starts, because `model.selection` is cleared the
                    // instant it succeeds.
                    staged = (model.selectedFileCount, model.selectedPhotoCount, model.savings)
                    Task {
                        await model.delete()
                        if model.outcome != nil {
                            // A files-only deletion can finish in under a tenth of a second,
                            // which would make the instrument a flicker. Long enough to be
                            // seen arriving, short enough not to be a fake wait: the work is
                            // already done either way.
                            try? await Task.sleep(for: .milliseconds(450))
                            dismiss()
                        }
                    }
                } label: {
                    Text("Delete \(Counting.items(model.selection.count))")
                }
                .buttonStyle(.key(DS.destructive, enabled: model.canDelete))
                .disabled(!model.canDelete)
                .transition(.opacity)
                .accessibilityIdentifier("confirm.delete")
            }
        }
        .padding(14)
        // The same floating dock as the review screen's, so the two bottoms of the two screens
        // in this flow are the same object rather than two edge-to-edge material strips.
        .dsDock()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(Motion.content, value: model.isDeleting)
        .sensoryFeedback(.impact(weight: .heavy), trigger: model.isDeleting) { _, started in started }
    }

    private func handover(_ staged: (files: Int, photos: Int, savings: SavingsBreakdown)) -> some View {
        SweeperRingView(
            scene: scene(staged),
            size: 118,
            caption: sweepCaption(staged),
            stepInterval: model.deletionStepInterval
        )
            .frame(maxWidth: .infinity)
            .dsSlab(padding: DS.Space.m, radius: DS.controlCorner)
    }

    /// What the ring says underneath itself. Never a percentage during the atomic half — that
    /// number does not exist there, and the arc is already saying so.
    private func sweepCaption(_ staged: (files: Int, photos: Int, savings: SavingsBreakdown)) -> String {
        if let outcome = model.outcome {
            return "\(Counting.items(outcome.deletedCount)) removed"
        }
        guard let progress = model.deletionProgress, progress.isDeterminate else {
            return "Settles in one step"
        }
        return "\(progress.settled) of \(progress.total)"
    }

    private func scene(_ staged: (files: Int, photos: Int, savings: SavingsBreakdown)) -> SweepScene {
        // Arrived. The sheet holds on this for a beat before dismissing, so the tick is seen
        // coming out of the ring rather than cut off by the transition.
        if model.outcome != nil { return .done }
        return .from(model.deletionProgress)
    }

    /// The gauge reading, set the same way as the disk on the overview so the two numbers read
    /// as measurements of the same thing.
    private var headline: some View {
        // Once the deletion has run, the selection is empty — so reading it here produced
        // "0 KB · nothing is selected" on the sheet at the exact moment it was meant to be
        // showing the arrival. Past that point the figure is what actually went.
        let done = model.outcome != nil
        let bytes = done
            ? (model.outcomeSavings ?? .empty).onDeviceBytes
            : model.savings.onDeviceBytes

        return VStack(alignment: .leading, spacing: 2) {
            Eyebrow(done ? "What went" : "Comes back to this device", tint: DS.deep)

            Readout.bytes(bytes, tint: DS.deep)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .accessibilityIdentifier("confirm.total")

            Text(deepestCostLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
        .animation(Motion.content, value: done)
    }

    private var deepestCostLine: String {
        if let outcome = model.outcome {
            return "\(Counting.items(outcome.deletedCount)) removed"
        }
        guard let tier = model.deepestSelectedTier else { return "nothing is selected" }
        return tier.isLossless
            ? "from \(Counting.items(model.selection.count)) that cost you nothing"
            : "from \(Counting.items(model.selection.count)), the dearest a judgement call"
    }

    /// A ledger rather than a card of rows: hairline-ruled, figures right-aligned and lined up
    /// on the digit, because this is the part someone actually audits.
    @ViewBuilder
    private var breakdown: some View {
        // Only the rows that carry something. The Recently Deleted row used to be
        // unconditional, so a selection made entirely of files in a Files folder — which are
        // gone the moment they are deleted — opened this sheet with "After emptying Recently
        // Deleted  0 KB" at the top and a paragraph about a thirty-day album that had nothing
        // to do with anything the user had picked.
        let rows = ledgerRows
        if !rows.isEmpty {
            Card("When you get it back", symbolName: "clock", identifier: "confirm.breakdown") {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.title) { index, entry in
                        if index > 0 {
                            Divider().overlay(DS.hairline)
                        }
                        row(entry.title, bytes: entry.bytes, note: entry.note)
                    }
                }
            }
        }
    }

    private struct LedgerRow {
        let title: String
        let bytes: Int64
        let note: String
    }

    private var ledgerRows: [LedgerRow] {
        let savings = model.savings
        var rows: [LedgerRow] = []

        if savings.immediateBytes > 0 {
            rows.append(
                LedgerRow(
                    title: "Right away",
                    bytes: savings.immediateBytes,
                    note: "Files deleted outside the photo library are gone immediately."
                )
            )
        }
        if savings.deferredBytes > 0 {
            rows.append(
                LedgerRow(
                    title: "After emptying Recently Deleted",
                    bytes: savings.deferredBytes,
                    note: "iOS keeps deleted photos for 30 days. The space returns when you empty that album, or when the 30 days are up."
                )
            )
        }
        if savings.cloudOnlyBytes > 0 {
            rows.append(
                LedgerRow(
                    title: "In iCloud only",
                    bytes: savings.cloudOnlyBytes,
                    note: "These originals are not on this device, so deleting them frees iCloud storage rather than local storage."
                )
            )
        }
        return rows
    }

    private var judgementWarning: some View {
        Card(
            "Not everything here is free",
            symbolName: "hand.raised",
            identifier: "confirm.judgement",
            rail: DS.tier(.similar)
        ) {
            Text("\(model.judgementCallCount) of the selected items are not provably redundant — they are similar shots or burst frames. Deleting them loses something, even if only a near-miss of a photo you kept.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func row(_ title: String, bytes: Int64, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(ByteFormatting.string(bytes))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
    }
}
