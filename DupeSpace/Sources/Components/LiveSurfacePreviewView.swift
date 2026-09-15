import SwiftUI
import DupeCore

/// Every state of the live scan surfaces, on one screen.
///
/// The Lock Screen and the Dynamic Island are the two places in this app that CI cannot walk to:
/// no simulator will show a Live Activity, and no screenshot can be taken of one. The views
/// themselves are ordinary SwiftUI, though — they live in `Shared` and compile into both targets
/// — so the app renders them here instead, and the automated walk photographs this.
///
/// Drawn in situ rather than as a list of dark pills. A Live Activity is a thing that appears on
/// a Lock Screen under a clock, with the island above it; shown out of that context it is just a
/// rounded rectangle, and nobody reviewing this screen can tell whether it would read at arm's
/// length on a phone in the dark. So the phone is drawn too.
///
/// Reachable only under `-ui-testing`. It is a test fixture, not a feature.
struct LiveSurfacePreviewView: View {

    let onClose: () -> Void

    /// A scan that started a minute and a half ago. A fixed date in the past made the running
    /// timer read "10885:58:46", which is the fixture being wrong rather than the view.
    private let started = Date().addingTimeInterval(-95)

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
            ),
            // The phase this sheet was missing, under a doc comment promising every state on
            // one screen — and the one whose bar used to draw completely full, in red, for a
            // scan that had got nowhere.
            (
                "Failed",
                LiveScanState(
                    phase: .failed,
                    stage: .fingerprinting,
                    completed: 1_450,
                    total: 5_000,
                    startedAt: started
                )
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // One state drawn in full context, and only one.
                    //
                    // Every state used to get its own phone: six drawn devices, each 372 points
                    // tall with a clock and a home indicator, so comparing "Running" with
                    // "Failed" meant scrolling a screen and a half between them and holding the
                    // first one in your head. A spec sheet's whole job is comparison. The phone
                    // is here once, to answer "does this read on a Lock Screen at arm's length",
                    // and after that the cards are stacked where the eye can run down them.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("On the Lock Screen")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)

                        LockScreenMock(state: states[0].1)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Every state")
                            .font(.system(.title3, design: .rounded).weight(.bold))

                        ForEach(Array(states.enumerated()), id: \.offset) { _, entry in
                            StateStrip(name: entry.0, state: entry.1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(DS.ink, ignoresSafeAreaEdges: .all)
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

/// One state, on the two surfaces it appears on, with the thing neither of them shows.
///
/// The island and the card sit on the dark ground they are drawn against on a phone, so their
/// contrast is reviewable; the line underneath is what VoiceOver reads out, which is the one
/// piece of information the mock genuinely cannot show. It used to repeat the card's own two
/// strings in plain black text under every mock — the same words twice, six times over, which
/// reads as debug output somebody forgot to delete.
private struct StateStrip: View {

    let name: String
    let state: LiveScanState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer(minLength: 8)
                // What the scan's percentage reads as in the island's tiny slot, which is the
                // one number on these surfaces with nowhere to grow and the first thing that
                // truncates.
                Text(state.compactValue)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                IslandPreview(state: state)
                ScanLockScreenView(state: state)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(dsRGB: 0x0A1218))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)

            Text(state.accessibilityDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A phone, asleep, with the scan on it.
///
/// Not a photograph and not pretending to be one: a drawn device, so the island keeps its real
/// shape and the activity card sits where iOS actually puts it — under the clock, inset from the
/// bezel by the same margin the system uses.
private struct LockScreenMock: View {

    let state: LiveScanState

    var body: some View {
        VStack(spacing: 0) {
            IslandPreview(state: state)
                .padding(.top, 11)

            VStack(spacing: -2) {
                Text("Monday 9 June")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("9:41")
                    .font(.system(size: 66, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.top, 18)

            Spacer(minLength: 18)

            ScanLockScreenView(state: state)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.black.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
                .padding(.horizontal, 14)

            Spacer(minLength: 16)

            Capsule()
                .fill(.white.opacity(0.7))
                .frame(width: 112, height: 5)
                .padding(.bottom, 9)
        }
        .frame(minHeight: 372)
        .frame(maxWidth: .infinity)
        .background(wallpaper)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(
            // The bezel. A flat 5-point band read as an outline drawn round a rectangle rather
            // than as a device: metal is lit, so the stroke is a gradient — brighter where a
            // light would be, darker underneath — and the whole thing casts a shadow so it sits
            // on the page instead of being printed on it.
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(dsRGB: 0x3A4654),
                            Color(dsRGB: 0x1B222B),
                            Color(dsRGB: 0x10161D)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 5
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                .padding(5)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    /// The icon's own gradient, turned down until it reads as a wallpaper someone might have.
    private var wallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [Color(dsRGB: 0x0A1520), Color(dsRGB: 0x04080C)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [DS.brandTop.opacity(0.30), .clear],
                center: .init(x: 0.78, y: 0.12),
                startRadius: 0,
                endRadius: 240
            )
            RadialGradient(
                colors: [DS.brandBottom.opacity(0.16), .clear],
                center: .init(x: 0.12, y: 0.92),
                startRadius: 0,
                endRadius: 220
            )
        }
    }
}

/// The compact presentation, drawn as the Dynamic Island lays it out: one black pill around the
/// sensor cutout, one slot either side of it.
private struct IslandPreview: View {

    let state: LiveScanState

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: state.symbolName)
                .font(.footnote)
                .foregroundStyle(ScanPalette.tint(for: state))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 34)

            // The hardware, at its real width. It is black on black, exactly as it is on a
            // phone — the two sensors are the only thing that gives it away.
            HStack(spacing: 7) {
                Circle().fill(.white.opacity(0.045)).frame(width: 9, height: 9)
                Circle().fill(.white.opacity(0.03)).frame(width: 5, height: 5)
            }
            .frame(width: 86, height: 30)

            Text(state.compactValue)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ScanPalette.tint(for: state))
                .frame(width: 46)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Capsule().fill(.black))
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dynamic Island: \(state.accessibilityDescription)")
    }
}
