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
                        Card("Nothing was deleted", symbolName: "exclamationmark.triangle", identifier: "confirm.failure") {
                            Text(failure)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(Motion.content, value: model.judgementCallCount)
                .animation(Motion.content, value: model.failure)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("confirm.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    Task {
                        await model.delete()
                        if model.outcome != nil { dismiss() }
                    }
                } label: {
                    if model.isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Delete \(Counting.items(model.selection.count))")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(!model.canDelete)
                .padding(16)
                .background(.regularMaterial)
                .sensoryFeedback(.impact(weight: .heavy), trigger: model.isDeleting) { _, started in started }
                .accessibilityIdentifier("confirm.delete")
            }
        }
    }

    private var headline: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(ByteFormatting.string(model.savings.onDeviceBytes))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("confirm.total")
                Text("comes back to this device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var breakdown: some View {
        Card("When you get it back", symbolName: "clock", identifier: "confirm.breakdown") {
            VStack(spacing: 0) {
                row(
                    "After emptying Recently Deleted",
                    bytes: model.savings.deferredBytes,
                    note: "iOS keeps deleted photos for 30 days. The space returns when you empty that album, or when the 30 days are up."
                )
                if model.savings.immediateBytes > 0 {
                    Divider()
                    row("Right away", bytes: model.savings.immediateBytes, note: "Files deleted outside the photo library are gone immediately.")
                }
                if model.savings.cloudOnlyBytes > 0 {
                    Divider()
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
        Card("Not everything here is free", symbolName: "hand.raised", identifier: "confirm.judgement") {
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
                    .font(.subheadline.weight(.semibold))
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
        .padding(.vertical, 8)
    }
}
