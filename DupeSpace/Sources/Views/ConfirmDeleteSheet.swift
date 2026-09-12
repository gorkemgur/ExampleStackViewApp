import SwiftUI
import DupeCore

/// The last screen before anything is destroyed.
///
/// It leads with what the user will actually get back and when, because "frees 12 GB" is a
/// lie if most of that sits in Recently Deleted for thirty days or belongs to originals that
/// were never on the device in the first place.
struct ConfirmDeleteSheet: View {

    @ObservedObject var model: ReviewViewModel
    @Environment(\.dismiss) private var dismiss

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

                    if let failure = model.failure {
                        Card(
                            "Nothing was deleted",
                            symbolName: "exclamationmark.triangle",
                            identifier: "confirm.failure",
                            rail: DS.tier(.similar)
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
        .buttonStyle(.key(.red, enabled: model.canDelete))
        .disabled(!model.canDelete)
        .padding(16)
        .background(.regularMaterial, ignoresSafeAreaEdges: .bottom)
        .sensoryFeedback(.impact(weight: .heavy), trigger: model.isDeleting) { _, started in started }
        .accessibilityIdentifier("confirm.delete")
    }

    /// The gauge reading, set the same way as the disk on the overview so the two numbers read
    /// as measurements of the same thing.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow("Comes back to this device", tint: DS.aqua)

            Readout.bytes(model.savings.onDeviceBytes, tint: DS.aqua)
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
    private var breakdown: some View {
        Card("When you get it back", symbolName: "clock", identifier: "confirm.breakdown") {
            VStack(spacing: 0) {
                row(
                    "After emptying Recently Deleted",
                    bytes: model.savings.deferredBytes,
                    note: "iOS keeps deleted photos for 30 days. The space returns when you empty that album, or when the 30 days are up."
                )
                if model.savings.immediateBytes > 0 {
                    Divider().overlay(DS.hairline)
                    row("Right away", bytes: model.savings.immediateBytes, note: "Files deleted outside the photo library are gone immediately.")
                }
                if model.savings.cloudOnlyBytes > 0 {
                    Divider().overlay(DS.hairline)
                    row(
                        "In iCloud only",
                        bytes: model.savings.cloudOnlyBytes,
                        note: "These originals are not on this device, so deleting them frees iCloud storage rather than local storage."
                    )
                }
            }
        }
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
