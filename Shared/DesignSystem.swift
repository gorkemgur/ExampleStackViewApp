import SwiftUI
import UIKit
import DupeCore

/// The app's material: one palette, one type scale, one set of shapes.
///
/// The palette is taken from the icon rather than from the system — `#0A84FF` at the top of the
/// gradient, `#32D7EB` at the bottom — so the Home Screen, the Lock Screen and the app are
/// recognisably the same thing. Everything else is derived from those two hues: the neutrals
/// carry a slight blue bias so they read as chosen rather than as `systemGray`, and the regret
/// ladder gets a cool-to-warm ramp that runs from the brand's teal to a coral, because the one
/// ordering this whole product hangs off is "what does deleting this cost me".
///
/// In `Shared/` rather than in the app, and that placement is the point. While it lived in the
/// app target the widget could not reach it, so the Home Screen widget drew its own
/// proportional bar and the Live Activity carried a third palette made of `.cyan`, `.orange`
/// and `.green` — nine stock system colours on the two surfaces a person sees most, including a
/// reversed, desaturated imitation of the icon's own gradient. Three independent colour systems
/// claiming to be one app is exactly what this file exists to prevent, so it is compiled into
/// everything that draws.
enum DS {

    // MARK: - Ground

    /// The page behind everything.
    static let ink = adaptive(light: 0xEFF3F8, dark: 0x080C11)
    /// A panel lifted off the page.
    static let inkRaised = adaptive(light: 0xFFFFFF, dark: 0x131A22)
    /// A recess: meter tracks, thumbnail wells, anything pressed into the panel.
    static let well = adaptive(light: 0xE2E9F1, dark: 0x0D1319)
    /// The one rule weight in the app.
    static let hairline = adaptive(light: 0xD6E0EA, dark: 0x232D38)
    /// A filled neutral, for the part of a measurement this app cannot act on.
    static let neutral = adaptive(light: 0xA5B4C4, dark: 0x46566A)

    /// The instrument panel. One value, not an adaptive pair: these blocks are drawn dark in
    /// both appearances so the figure on them can carry the brand gradient at full saturation,
    /// and they force `colorScheme` to dark for the system controls they hold — which would
    /// resolve an adaptive colour to its dark half anyway. Used for the three blocks that are
    /// the product: the invitation to scan, what the scan found, and the space budget.
    static let slab = Color(dsRGB: 0x101B27)
    /// Body copy on `slab`.
    static let onSlab = Color(dsRGB: 0xE7F0F8)

    // MARK: - Brand

    /// Text-safe blue, and the app's only accent. Darker than `#0A84FF` in light mode, where
    /// the icon's blue on white is only just readable at caption sizes.
    ///
    /// There used to be a second one — `aqua`, `#0C8FA3` / `#32D7EB` — whose doc said it was
    /// the brand's other voice. Its two values were character-for-character the two values of
    /// `tier(.identical)`. So every eyebrow, every card glyph and every readout unit in the app
    /// was painted in "identical copies, costs nothing", and on the results screen a heading, a
    /// unit and a meter segment forty points apart were the same hue meaning two different
    /// things. One hue, one meaning: the accent is this, the ladder is the ladder.
    static let deep = adaptive(light: 0x0A6FE0, dark: 0x3DA1FF)

    /// The accent, on `slab`. The light-mode `deep` is too dark for a navy ground and the
    /// dark-mode one is not quite bright enough.
    static let onSlabAccent = Color(dsRGB: 0x7FC4FF)

    /// The icon's own two stops. Fills only — never text on a light ground.
    static let brandTop = Color(dsRGB: 0x0A84FF)
    static let brandBottom = Color(dsRGB: 0x32D7EB)

    /// The colour of a thing that cannot be undone. Used in exactly one place: the key that
    /// destroys files. It was on four controls, three of which only opened a sheet or armed a
    /// choice — and a warning colour spent on reversible things is a warning colour nobody
    /// reads by the time it matters.
    static let destructive = adaptive(light: 0xE5342B, dark: 0xFF5247)

    static var brand: LinearGradient {
        LinearGradient(colors: [brandTop, brandBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var brandRow: LinearGradient {
        LinearGradient(colors: [brandTop, brandBottom], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - The regret ladder

    /// A tier's colour. Cool at the bottom of the ladder where deletion is free, warm at the top
    /// where it costs something — so a rail, a dot or a rung says what it costs before the words
    /// do. Deliberately not the accent: this is a semantic scale, not branding.
    static func tier(_ tier: RegretTier) -> Color {
        switch tier {
        case .identical: return adaptive(light: 0x0C7C8E, dark: 0x32D7EB)
        case .inferiorCopy: return adaptive(light: 0x10805F, dark: 0x3DDC97)
        case .burstLeftover: return adaptive(light: 0x996100, dark: 0xF5B944)
        case .similar: return adaptive(light: 0xBC4127, dark: 0xF2684E)
        }
    }

    /// The same ladder at full saturation, for use on `slab`, which is dark in both
    /// appearances — the light-mode tier colours are darkened for text on white and would
    /// disappear there.
    static func tierVivid(_ tier: RegretTier) -> Color {
        switch tier {
        case .identical: return Color(dsRGB: 0x32D7EB)
        case .inferiorCopy: return Color(dsRGB: 0x3DDC97)
        case .burstLeftover: return Color(dsRGB: 0xF5B944)
        case .similar: return Color(dsRGB: 0xF2684E)
        }
    }

    /// What that tier costs, in two words, for the rung's eyebrow.
    static func cost(_ tier: RegretTier) -> String {
        tier.isLossless ? "Costs nothing" : "Your call"
    }

    // MARK: - Metrics

    /// Every corner in the app is one of these. There were thirteen distinct literals across
    /// the views and two tokens, which is not a shape language, it is thirteen decisions nobody
    /// made twice the same way.
    static let corner: CGFloat = 20
    static let slabCorner: CGFloat = 24
    static let controlCorner: CGFloat = 15
    static let wellCorner: CGFloat = 12
    static let chipCorner: CGFloat = 9
    static let railWidth: CGFloat = 4

    /// A 4pt grid. `spacing: 2` is the one exception, for a label sitting directly on top of
    /// the figure it names, where the two are meant to read as one block.
    enum Space {
        static let tight: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 32
    }

    // MARK: - Plumbing

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dsRGB: dark) : UIColor(dsRGB: light)
        })
    }
}

extension UIColor {

    convenience init(dsRGB value: UInt32) {
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {

    init(dsRGB value: UInt32) {
        self.init(uiColor: UIColor(dsRGB: value))
    }
}

// MARK: - Type

/// A byte count set as an instrument reads it: the figure heavy and rounded, the unit smaller
/// and tinted, both in one `Text` so it stays a single accessibility element that VoiceOver
/// reads as "2.02 GB" and a UI test can query by identifier.
enum Readout {

    static func bytes(
        _ value: Int64,
        scale: Font.TextStyle = .largeTitle,
        unitScale: Font.TextStyle = .title3,
        tint: Color = DS.deep
    ) -> Text {
        // `ByteText` from the engine rather than the app-side `ByteFormatting` wrapper around
        // it: this file is compiled into the widget extension too, and the wrapper is not.
        let formatted = ByteText.string(value)
        let parts = formatted.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)

        let figureFont = Font.system(scale, design: .rounded).weight(.heavy)
        guard parts.count == 2 else {
            return Text(formatted).font(figureFont)
        }

        return Text(String(parts[0])).font(figureFont)
            + Text(" ")
            + Text(String(parts[1]))
                .font(.system(unitScale, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
    }
}

/// The small wide-tracked label that sits over a figure. The counterweight to the hero number:
/// the whole point of the pairing is that one is loud and the other is quiet, and a caption set
/// in the same grey subheadline as the body copy is neither.
struct Eyebrow: View {

    private let text: String
    private let tint: Color

    init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .kerning(0.9)
            .foregroundStyle(tint)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Shapes

extension View {

    /// The panel every carded thing in the app sits on: a fill, a hairline, no drop shadow.
    /// Shadow says "floating"; nothing in this app floats.
    func dsPanel(radius: CGFloat = DS.corner, fill: Color = DS.inkRaised) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 1)
        )
    }

    /// A recess for a track, a chip or a thumbnail.
    func dsWell(radius: CGFloat = DS.wellCorner) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(DS.well)
        )
    }

    /// The instrument panel: a dark slab with a lit edge, holding a reading and the control
    /// that moves it.
    ///
    /// This was three byte-identical copies of the same eight lines, in the three files that
    /// draw the product's three main blocks. The material that says "this is the instrument,
    /// not another section" is exactly the thing that must not be re-typed per screen.
    func dsSlab(padding: CGFloat = DS.Space.xl) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.slabCorner, style: .continuous).fill(DS.slab)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.slabCorner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
    }
}

/// The one button shape in the app: a wide rounded rectangle, never a pill. A capsule reads as
/// "iOS default"; this reads as a key on a panel.
struct KeyButtonStyle: ButtonStyle {

    var fill: AnyShapeStyle = AnyShapeStyle(DS.brandRow)
    var foreground: Color = .white
    var height: CGFloat = 52
    var isEnabled: Bool = true
    /// Full width by default. A key that shares a row with a reading hugs its label instead.
    var expands: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        Face(style: self, configuration: configuration)
    }

    /// A view of its own rather than a modifier chain in `makeBody`: `@Environment` is only
    /// honoured inside a `View`, and a `ButtonStyle` is not one.
    private struct Face: View {

        let style: KeyButtonStyle
        let configuration: ButtonStyleConfiguration

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// `.disabled(…)` on the button sets this, and it is the only signal most call sites
        /// give. Without reading it a disabled key kept the full brand gradient and its white
        /// label: a button that looks like the most important thing on the screen and does
        /// nothing when tapped.
        @Environment(\.isEnabled) private var isEnabled

        private var isLive: Bool { style.isEnabled && isEnabled }

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(isLive ? style.foreground : Color.secondary)
                .frame(maxWidth: style.expands ? .infinity : nil)
                .frame(minHeight: style.height)
                .background(
                    RoundedRectangle(cornerRadius: DS.controlCorner, style: .continuous)
                        .fill(isLive ? style.fill : AnyShapeStyle(DS.well))
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.controlCorner, style: .continuous))
                .opacity(configuration.isPressed && isLive ? 0.82 : 1)
                .scaleEffect(configuration.isPressed && isLive && !reduceMotion ? 0.985 : 1)
                .animation(Motion.control, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == KeyButtonStyle {

    static var key: KeyButtonStyle { KeyButtonStyle() }

    /// The brand key, with an explicit enabled state and an optional hug.
    static func key(enabled: Bool = true, expands: Bool = true) -> KeyButtonStyle {
        KeyButtonStyle(isEnabled: enabled, expands: expands)
    }

    /// A key that carries a meaning rather than the brand. One caller: the key that destroys
    /// files, in `DS.destructive`.
    static func key(_ color: Color, enabled: Bool = true, expands: Bool = true) -> KeyButtonStyle {
        KeyButtonStyle(
            fill: AnyShapeStyle(color),
            foreground: .white,
            isEnabled: enabled,
            expands: expands
        )
    }

    /// The quiet key: a hairlined well, for secondary actions.
    static var keyQuiet: KeyButtonStyle {
        KeyButtonStyle(fill: AnyShapeStyle(DS.well), foreground: DS.deep)
    }
}

/// A proportional strip of segments. Used for the disk, for the library breakdown and for the
/// ladder's reach, so the same measurement always looks the same.
struct MeterTrack: View {

    struct Segment: Identifiable, Equatable {
        let id: String
        let value: Double
        let color: Color
        var isMuted: Bool = false
    }

    let segments: [Segment]
    /// The denominator. Anything the segments do not account for reads as empty track.
    let total: Double
    var height: CGFloat = 10
    /// How a change in the segments is drawn.
    ///
    /// This used to be fixed at `Motion.content` — a 0.32s spring — inside the track itself,
    /// which is right for the disk gauge and the reach ramp, where the value changes when
    /// somebody does something, and wrong for the scan progress bar, where it changes several
    /// times a second. There the spring restarted before it had settled, every tick, for the
    /// length of the scan: a bar that never arrives anywhere is read as a bar that is stuck.
    /// The caller knows which kind of quantity it is holding; the track does not.
    var motion: Animation? = Motion.content

    var body: some View {
        GeometryReader { proxy in
            // One shape, not a row of rounded slugs with gaps between them. This measures a
            // single disk, and a single quantity drawn as separate pieces reads as three
            // unrelated things. The colour change is the boundary; it needs no gap to be seen.
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    // A muted segment is neutral, not a faded version of its own colour.
                    // Amber at 22% over the slab composites to an olive-brown that is in no
                    // palette in this app, and the ladder's warm end was the part most often
                    // muted — so "space this plan will not touch" was drawn in mud.
                    Rectangle()
                        .fill(segment.isMuted ? AnyShapeStyle(DS.neutral.opacity(0.35)) : AnyShapeStyle(segment.color))
                        .frame(width: width(for: segment.value, in: proxy.size.width))
                }
                Rectangle()
                    .fill(DS.well)
            }
            .clipShape(Capsule(style: .continuous))
            // The empty end of the track is DS.well, which sits a shade off the page it is
            // drawn on — enough on a white card, not enough on the page itself, where the bar
            // simply stopped in mid-air. The edge says how long the whole disk is.
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
        }
        .frame(height: height)
        .animation(motion, value: segments)
    }

    private func width(for value: Double, in available: CGFloat) -> CGFloat {
        guard total > 0, value > 0 else { return 0 }
        let fraction = min(value / total, 1)
        // A hairline for anything real but tiny: "you have 40 MB of duplicates" must not
        // render as nothing at all.
        return max(available * fraction, 3)
    }
}

/// An ordinal choice, drawn as a reach rather than as three buttons.
///
/// The app hand-builds its key, argues about capsules and refuses drop shadows, and then made
/// the two most consequential choices in the product — how far down the ladder a plan may
/// reach, and how alike counts as a copy — in a stock `.pickerStyle(.segmented)`. On the dark
/// slab that control renders grey on grey, so the selected option was the hardest thing on the
/// screen to see. It is also the single most recognisable iOS component there is, which is
/// most of what "this looks like every other app" means.
///
/// Both choices are positions on a scale, not three unrelated options, so this draws them as
/// one: a track that fills from the left up to and including the chosen step, in that step's
/// own colour. It is the same bar the disk, the library breakdown and the ladder's reach are
/// drawn with, which means "how far am I willing to go" and "how much do I get back" are
/// finally the same picture.
struct ReachPicker<Value: Hashable>: View {

    struct Option: Identifiable {
        let value: Value
        let title: String
        /// The colour this step fills the track with once it is reached.
        let color: Color

        var id: Value { value }
    }

    @Binding var selection: Value
    let options: [Option]
    /// Base for each step's accessibility identifier, so a walk can tap a specific one.
    var identifier: String
    /// Labels on a dark slab need the slab's own foreground.
    var onSlab: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedIndex: Int {
        options.firstIndex { $0.value == selection } ?? 0
    }

    var body: some View {
        VStack(spacing: DS.Space.s) {
            track

            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    Button {
                        withAnimation(reduceMotion ? nil : Motion.control) {
                            selection = option.value
                        }
                    } label: {
                        Text(option.title)
                            .font(.footnote.weight(index == selectedIndex ? .bold : .medium))
                            .foregroundStyle(labelColor(at: index, option: option))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            // The whole column is the target, not just the glyphs in it.
                            .frame(minHeight: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(identifier).\(index)")
                    .accessibilityAddTraits(index == selectedIndex ? [.isSelected] : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var track: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Rectangle()
                    .fill(index <= selectedIndex ? option.color : (onSlab ? Color.white.opacity(0.10) : DS.well))
            }
        }
        .frame(height: 10)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(onSlab ? Color.white.opacity(0.14) : DS.hairline, lineWidth: 1)
        )
        .animation(reduceMotion ? nil : Motion.control, value: selectedIndex)
        .accessibilityHidden(true)
    }

    private func labelColor(at index: Int, option: Option) -> Color {
        guard index == selectedIndex else {
            return onSlab ? DS.onSlab.opacity(0.55) : .secondary
        }
        return option.color
    }
}
