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
                    breakdown

                    if model.judgementCallCount > 0 {
                        judgementWarning
                    }

                    keepACopy

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
    private var deleteKey: some View {
        Button(role: .destructive) {
            Task {
                await model.delete()
                if model.outcome != nil { dismiss() }
            }
        } label: {
            if model.isDeleting {
                // Not tinted white: while the deletion runs the key is disabled, so it is a
                // grey well, and a white spinner on it is an invisible spinner.
                ProgressView()
                    .tint(DS.deep)
            } else {
                Text("Delete \(Counting.items(model.selection.count))")
            }
        }
        .buttonStyle(.key(DS.destructive, enabled: model.canDelete))
        .disabled(!model.canDelete)
        .padding(14)
        // The same floating dock as the review screen's, so the two bottoms of the two screens
        // in this flow are the same object rather than two edge-to-edge material strips.
        .dsDock()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .sensoryFeedback(.impact(weight: .heavy), trigger: model.isDeleting) { _, started in started }
        .accessibilityIdentifier("confirm.delete")
    }

    /// The gauge reading, set the same way as the disk on the overview so the two numbers read
    /// as measurements of the same thing.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow("Comes back to this device", tint: DS.deep)

            Readout.bytes(model.savings.onDeviceBytes, tint: DS.deep)
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
    }

    private var deepestCostLine: String {
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
