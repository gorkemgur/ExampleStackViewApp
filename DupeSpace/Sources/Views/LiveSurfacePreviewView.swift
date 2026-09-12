import SwiftUI
import DupeCore

/// Every state of the live scan surfaces, on one screen.
///
/// The Lock Screen and the Dynamic Island are the two places in this app that CI cannot walk to:
/// no simulator will show a Live Activity, and no screenshot can be taken of one. The views
/// themselves are ordinary SwiftUI, though — they live in `Shared` and compile into both targets
/// — so the app renders them here instead, and the automated walk photographs this.
///
/// Reachable only under `-ui-testing`. It is a test fixture, not a feature.
struct LiveSurfacePreviewView: View {

    let onClose: () -> Void

    private let started = Date(timeIntervalSince1970: 1_750_000_000)

    private var states: [(String, LiveScanState)] {
        [
            (
                "Running",
                LiveScanState(
                    phase: .scanning,
                    stage: .fingerprinting,
                    completed: 1_204,
                    total: 5_000,
                    startedAt: started
                )
            ),
            (
                "Held",
                LiveScanState(
                    phase: .paused,
                    stage: .hashing,
                    completed: 2_600,
                    total: 5_000,
                    startedAt: started
                )
            ),
            (
                "Finished, something found",
                LiveScanState(
                    phase: .finished,
                    stage: .planning,
                    completed: 5_000,
                    total: 5_000,
                    candidateCount: 128,
                    reclaimableBytes: 4_300_000_000,
                    startedAt: started
                )
            ),
            (
                "Finished, nothing found",
                LiveScanState(
                    phase: .finished,
                    stage: .planning,
                    completed: 5_000,
                    total: 5_000,
                    startedAt: started
                )
            ),
            (
                "Stopped",
                LiveScanState(
                    phase: .cancelled,
                    stage: .hashing,
                    completed: 900,
                    total: 5_000,
                    startedAt: started
                )
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(Array(states.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.0)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            IslandPreview(state: entry.1)

                            ScanLockScreenView(state: entry.1, total: 5_000)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(.black.opacity(0.85))
                                )
                                .environment(\.colorScheme, .dark)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Live surfaces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose)
                        .accessibilityIdentifier("livepreview.close")
                }
            }
        }
        .accessibilityIdentifier("livepreview.root")
    }
}

/// The compact presentation, drawn as the Dynamic Island lays it out: the sensor cutout in the
/// middle, one slot either side.
private struct IslandPreview: View {

    let state: LiveScanState

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: state.symbolName)
                .font(.footnote)
                .foregroundStyle(ScanPalette.tint(for: state))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 36)

            Capsule()
                .fill(.black)
                .frame(width: 86, height: 30)

            Text(state.compactValue)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ScanPalette.tint(for: state))
                .frame(width: 46)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(Capsule().fill(.black))
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
