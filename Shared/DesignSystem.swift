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
    static let slab = Color(dsRGB: 0x18293C)

    /// The slab as it is actually painted: lit from the top, not flat.
    ///
    /// `#101B27` on a `#EFF3F8` page is nearly a black rectangle, and a large flat block that
    /// dark reads as a hole cut in the screen rather than as a panel resting on it. Two things
    /// fix that without giving up the dark instrument: the base is lifted to a deep slate-blue
    /// that still lets the brand gradient sit at full saturation on it, and the fill carries a
    /// slight vertical lift so the top edge catches light the way a real panel would.
    static var slabFill: LinearGradient {
        LinearGradient(
            colors: [Color(dsRGB: 0x1E3145), Color(dsRGB: 0x13202F)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
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

    /// The colour those two words are set in.
    ///
    /// Not the tier's own colour, which put the identical words "COSTS NOTHING" on screen
    /// twice in two different hues, one teal and one green, directly under each other — a
    /// reader has to stop and work out whether the colour means something the words do not.
    /// There are two states here, so there are two colours: quiet for the rungs that cost
    /// nothing, the ladder's warning amber for the ones that are a judgement call. The rail
    /// beside the row still says which rung it is.
    /// The parameters are `rung` and `isOnSlab` because `tier` and `onSlab` are both names
    /// this type already uses — a five-line body had two shadowed names in it.
    static func costTint(_ rung: RegretTier, isOnSlab: Bool = false) -> Color {
        guard !rung.isLossless else {
            return isOnSlab ? onSlabMuted : .secondary
        }
        return isOnSlab ? tierVivid(.burstLeftover) : tier(.burstLeftover)
    }

    /// Secondary copy on the slab. `Color.secondary` resolves against the page, not against a
    /// navy block that ignores the appearance.
    static let onSlabMuted = Color(dsRGB: 0x8FA3B8)

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
    private let carriesSlug: Bool

    /// - Parameter slug: draws the tint as a short bar before the words.
    ///
    /// For an eyebrow that names a segment of a bar elsewhere on the screen. The overview's
    /// headline is the library's own figure and the library is a sliver of the disk gauge
    /// below it; without a slug that sliver was a colour on a bar with nothing anywhere
    /// saying what it was.
    init(_ text: String, tint: Color = .secondary, slug: Bool = false) {
        self.text = text
        self.tint = tint
        self.carriesSlug = slug
    }

    var body: some View {
        HStack(spacing: 6) {
            if carriesSlug {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: 14, height: 3)
            }
            Text(text)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .kerning(0.9)
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
                RoundedRectangle(cornerRadius: DS.slabCorner, style: .continuous).fill(DS.slabFill)
            )
            .overlay(
                // A brighter edge at the top than at the bottom, which is what makes a panel
                // look like it is sitting on the page rather than punched through it.
                RoundedRectangle(cornerRadius: DS.slabCorner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .environment(\.colorScheme, .dark)
    }
}

/// The one button shape in the app: a wide rounded rectangle, never a pill. A capsule reads as
/// "iOS default"; this reads as a key on a panel.
struct KeyButtonStyle: ButtonStyle {

    /// The key's own gradient, not the brand row.
    ///
    /// `brandRow` runs to `#32D7EB`, and white text on that end measures 1.74:1 — a centred
    /// label sat at about 2.49:1, under the 3:1 floor for large text across most of the
    /// button. The brand still reads, because the gradient is still the icon's two hues; it
    /// just stops before the point where nothing can be printed on it. `brandRow` keeps its
    /// job on the fader's track, where nothing is set on top of it.
    static let keyFill = LinearGradient(
        colors: [Color(dsRGB: 0x0A6FE0), Color(dsRGB: 0x0C8FBE)],
        startPoint: .leading,
        endPoint: .trailing
    )

    var fill: AnyShapeStyle = AnyShapeStyle(KeyButtonStyle.keyFill)
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
        /// The colour this step carries once it is reached.
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
        HStack(spacing: DS.Space.s) {
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
                        // A full 44pt. The simulator audit caught this control at 34 on its
                        // first run — a stock segmented picker is 32 and gets away with it
                        // because the system draws it; a hand-built one earns the height.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .background(chip(at: index, option: option))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifier).\(index)")
                .accessibilityAddTraits(index == selectedIndex ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// Chips, not a track.
    ///
    /// This used to draw a 10pt filled capsule with a hairline border, 23pt below a 16pt
    /// filled capsule with a hairline border that *is* draggable. Same affordance, different
    /// behaviour: the bar promised the interaction the fader above it has, while only the
    /// label columns underneath actually responded — and the bar itself was hidden from
    /// VoiceOver, so it was decoration that looked like a control.
    ///
    /// The ordinal reading survives, because every step up to and including the chosen one is
    /// filled: the row still says "this far", not "this one". The reach as a *measurement*
    /// moves to the one place it can be measured — the fader's own track, which now greys out
    /// everything this setting forbids.
    @ViewBuilder
    private func chip(at index: Int, option: Option) -> some View {
        let reached = index <= selectedIndex
        RoundedRectangle(cornerRadius: DS.chipCorner, style: .continuous)
            .fill(reached ? option.color.opacity(index == selectedIndex ? 0.22 : 0.12) : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: DS.chipCorner, style: .continuous)
                    .strokeBorder(
                        index == selectedIndex ? option.color.opacity(0.6) : unreached,
                        lineWidth: 1
                    )
            )
            .animation(reduceMotion ? nil : Motion.control, value: selectedIndex)
    }

    /// The outline of a step this setting has not reached.
    private var unreached: Color {
        onSlab ? Color.white.opacity(0.10) : DS.well
    }

    private func labelColor(at index: Int, option: Option) -> Color {
        guard index == selectedIndex else {
            return onSlab ? DS.onSlab.opacity(0.55) : .secondary
        }
        return option.color
    }
}

/// The target control: a fader, not a stock slider.
///
/// `Slider` is the single most recognisable iOS control there is — a hairline track and a
/// white circle — and on a dark instrument slab it reads as a system default dropped into a
/// designed screen, which is most of what "this looks like every other app" means. It also
/// says nothing: the one question this screen asks is *how far down the ladder does this
/// target make me go*, and a plain track cannot answer it.
///
/// So the track carries the ladder. Each rung is drawn behind the fill at its real width, in
/// its own colour at low opacity, so before you drag you can already see where "costs nothing"
/// runs out and the judgement calls begin. The fill is the brand; the grip is a fader cap.
/// Crossing a rung boundary is a selection haptic, because that is the moment the answer to
/// the question changes.
///
/// `accessibilityRepresentation` keeps it a real slider to VoiceOver and to XCUITest, so
/// `adjust(toNormalizedSliderPosition:)` still drives it.
struct TargetSlider: View {

    /// One rung of the ladder, in the order the plan reaches them.
    struct Rung: Identifiable {
        let id: String
        let bytes: Double
        let color: Color
    }

    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Drawn behind the fill. Empty draws a plain track.
    var rungs: [Rung] = []
    /// Bytes the current depth setting actually allows, or `nil` for no limit.
    ///
    /// Without it the fader offered, coloured and buzzed for space the plan would not take:
    /// the range is every candidate in every tier, but the plan only draws from tiers at or
    /// below the chosen depth. So you dragged into the amber, the readout said "I NEED 9 GB
    /// back", and the sentence twenty points below answered "only 2.02 GB is available at this
    /// setting" — the card contradicting itself between two controls you can see at once.
    var reachLimit: Double?
    /// A short description of the quantity, for VoiceOver.
    var label: String
    var identifier: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True for the whole of a drag. The fill must not animate while a finger is on it — a
    /// 0.15s curve re-run on every touch-move leaves the cap trailing the finger for the
    /// length of the gesture — but it should animate when the value moves for any other
    /// reason, such as a deletion pulling the ceiling down.
    @GestureState private var isDragging = false

    private let trackHeight: CGFloat = 16
    private let gripWidth: CGFloat = 7
    private let gripHeight: CGFloat = 30
    /// The control is 30pt of paint in a 44pt target.
    private let hitHeight: CGFloat = 44

    private var span: Double { max(range.upperBound - range.lowerBound, 1) }

    private var fraction: Double {
        min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// Where the current depth setting stops, as a fraction of the track.
    private var limitFraction: Double {
        guard let reachLimit else { return 1 }
        return min(max((reachLimit - range.lowerBound) / span, 0), 1)
    }

    /// Which rung the current target reaches into. Drives the haptic.
    ///
    /// Only rungs the plan can actually take: a haptic for crossing into bursts the setting
    /// forbids is the control congratulating you on a move it will not make.
    private var reachedRung: String {
        var consumed = 0.0
        let target = min(value - range.lowerBound, (reachLimit ?? range.upperBound) - range.lowerBound)
        for rung in rungs {
            consumed += rung.bytes
            if target <= consumed { return rung.id }
        }
        return rungs.last?.id ?? ""
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            // One width for the fill and one origin for the cap, derived from each other.
            // They used to live in two coordinate spaces — the fill spanned 0...width, the cap
            // travelled 0...(width - gripWidth) — so they agreed only in the middle and left a
            // visible notch at both ends.
            let fillWidth = fraction > 0 ? max(width * fraction, gripWidth) : 0

            ZStack(alignment: .leading) {
                ladder(in: width)
                    .frame(height: trackHeight)
                    .clipShape(Capsule(style: .continuous))

                Capsule(style: .continuous)
                    .fill(DS.brandRow)
                    .frame(width: fillWidth, height: trackHeight)

                // Where the depth setting stops. Everything past it is space this plan will
                // not take however far the target is dragged.
                if limitFraction < 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 2, height: trackHeight)
                        .offset(x: width * limitFraction - 1)
                }

                RoundedRectangle(cornerRadius: gripWidth / 2, style: .continuous)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: gripWidth / 2, style: .continuous)
                            .strokeBorder(DS.slab.opacity(0.35), lineWidth: 1)
                    )
                    .frame(width: gripWidth, height: gripHeight)
                    .offset(x: max(fillWidth - gripWidth / 2, 0))
            }
            .frame(height: hitHeight)
            .contentShape(Rectangle())
            // Anywhere on the track, not only on the grip: a 7pt cap is a hard thing to catch
            // and there is no reason to make someone catch it.
            //
            // But `minimumDistance: 0` is wrong here, and `CompareSliderView` already learned
            // why — at zero the gesture claims the touch the instant a finger lands, so a
            // scroll that happens to begin on this track sets a target instead of scrolling,
            // and a stray tap moves the budget. One point of travel is enough to tell a drag
            // from a touch, and a stock Slider does neither of those things.
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { drag in
                        let position = min(max(drag.location.x / max(width, 1), 0), 1)
                        value = range.lowerBound + position * span
                    }
            )
            .animation(isDragging || reduceMotion ? nil : Motion.readout, value: fraction)
        }
        .frame(height: hitHeight)
        .sensoryFeedback(.selection, trigger: reachedRung)
        // Without a label and a value this announced "fifty per cent, slider" — the byte
        // figure, which is the entire point of the control, never reached the user.
        .accessibilityRepresentation {
            Slider(value: $value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(ByteText.string(Int64(value)))
                .accessibilityIdentifier(identifier)
        }
    }

    /// The ladder, at rest, behind the fill.
    ///
    /// Normalised to `span`, the same denominator the fill uses — not to the sum of the rungs.
    /// The two are only equal when every rung is present and they add up exactly to the range,
    /// and a rung worth nothing is dropped before this ever sees it. Any other denominator and
    /// the fill stops somewhere the colours say a different rung begins, which is the one thing
    /// this control exists to say. The trailing rectangle takes up whatever is left.
    ///
    /// Rungs past the depth limit are drawn at a tenth of the strength: they are still on the
    /// track, because the space is real, but they are visibly not on offer.
    private func ladder(in width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(laidOutRungs, id: \.rung.id) { entry in
                Rectangle()
                    .fill(entry.rung.color.opacity(entry.isBeyondLimit ? 0.08 : 0.30))
                    .frame(width: max(width * entry.share, 2))
            }
            Rectangle().fill(Color.white.opacity(0.10))
        }
    }

    private struct LaidOutRung {
        let rung: Rung
        /// Fraction of the whole track this rung occupies.
        let share: Double
        /// True once the rung starts past the depth limit.
        let isBeyondLimit: Bool
    }

    /// Each rung with its share of the track and whether the depth setting has already run out
    /// by the time it starts. Computed in one pass rather than accumulated inside the view
    /// body, where a running total would be captured by a `ForEach` closure and never updated.
    private var laidOutRungs: [LaidOutRung] {
        var travelled = 0.0
        return rungs.map { rung in
            let share = max(rung.bytes, 0) / span
            let entry = LaidOutRung(rung: rung, share: share, isBeyondLimit: travelled >= limitFraction)
            travelled += share
            return entry
        }
    }
}

extension View {

    /// A floating dock: the bar that carries a reading and the action on it.
    ///
    /// Not `glassEffect`. It was, for one build, and the screenshot is the argument: Liquid
    /// Glass refracts what is behind it, and what is behind this dock is a dense list of
    /// filenames and byte figures — so the reading printed *on* the dock came out smeared and
    /// colour-fringed, and "YOU GET BACK 2.02 GB", the most important number on the screen,
    /// was the hardest thing on it to read. Glass belongs over quiet content. A bar carrying
    /// a figure someone is about to act on is not a place to bend light.
    ///
    /// The complaint that started this was the shape, not the material: an edge-to-edge band
    /// welded to the bottom edge. Inset, rounded and lifted off the page, over the app's own
    /// material, it reads as a panel resting on the list — and the figure on it stays legible.
    func dsDock() -> some View {
        background(
            RoundedRectangle(cornerRadius: DS.slabCorner, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.slabCorner, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 14, y: 4)
    }
}

/// The selection mark: drawn, not an SF Symbol.
///
/// `checkmark.square.fill` / `minus.square.fill` / `square` are the stock tri-state, and they
/// are stock in the way that matters — the corner radius, the weight of the tick and the
/// hairline of the empty box all belong to the system's shape language rather than to this
/// app's. They also change *size* between states, because the filled and unfilled symbols have
/// different optical weights, so a list of them shifts as you tick it.
///
/// One shape, three states, the app's own corner radius, and the tint is the rung's colour so
/// a tick says which part of the ladder it belongs to.
struct TickBox: View {

    /// Named `Mark` rather than `State`, and `empty/partial/full` rather than
    /// `none/some/all`. A nested `State` shadows `SwiftUI.State` inside this type, so the day
    /// someone adds an `@State` here the error names the wrong thing entirely; and
    /// `.none`/`.some` are how an `Optional` is spelled, so a function returning one reads as
    /// returning an optional.
    enum Mark {
        case empty, partial, full
    }

    let state: Mark
    let tint: Color
    var side: CGFloat = 24

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape
                .fill(state == .empty ? Color.clear : tint)

            shape
                .strokeBorder(state == .empty ? DS.neutral : .clear, lineWidth: 1.5)

            switch state {
            case .empty:
                EmptyView()
            case .partial:
                // A bar, not a minus glyph: the same stroke weight as the tick, so the two
                // states weigh the same on the row.
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: side * 0.46, height: side * 0.115)
            case .full:
                Tick()
                    .stroke(.white, style: StrokeStyle(lineWidth: side * 0.115, lineCap: .round, lineJoin: .round))
                    .frame(width: side * 0.5, height: side * 0.38)
            }
        }
        .frame(width: side, height: side)
        .animation(Motion.control, value: state)
    }
}

/// The checkmark itself. Three points, drawn to this app's proportions rather than the
/// system's — shallower and wider, so it reads at 24pt without looking cramped.
private struct Tick: Shape {

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.06))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
