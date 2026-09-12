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

    /// The three blocks that are the product: the invitation to scan, what the scan found, and
    /// the space budget.
    ///
    /// These were one dark value in both appearances — an instrument panel, deliberately not a
    /// card. It made the app heavy, and the argument for it never survived contact: the panel
    /// forced `colorScheme` to dark for everything inside it, which meant the ladder had to be
    /// painted twice (`tier` for paper, `tierVivid` for navy) and half the palette existed in
    /// two versions of itself. Every one of the light-mode values had been drawn for text on
    /// white and then never used on white.
    ///
    /// They are elevated cards now, and the depth comes from the three things that make one:
    /// a background step off the page, a hairline, and a shadow. The token keeps its name,
    /// because the *role* did not change — it is still the block that carries the product —
    /// and a rename would have touched eighty call sites to say the same thing.
    static let slab = adaptive(light: 0xFFFFFF, dark: 0x171E27)

    /// The slab as it is actually painted: lit from the top, not flat.
    static var slabFill: LinearGradient {
        LinearGradient(
            colors: [adaptive(light: 0xFFFFFF, dark: 0x1B2430), adaptive(light: 0xF8FAFD, dark: 0x141B25)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The slab's own edge. A hairline on paper, a lift in the dark.
    static let slabEdge = adaptive(light: 0xDCE4EE, dark: 0x2A3542)

    /// A recess *on* the slab: the fader's groove, an unreached step, the part of a track that
    /// is not on offer. It has to read as cut into the card rather than as a colour laid on it.
    static let groove = adaptive(light: 0xD7DEE8, dark: 0x2B3644)

    /// Ink, for the one thing on this screen that is white in both appearances: the fader cap.
    /// Its stroke and its ridges cannot come from an adaptive pair, because the thing they are
    /// drawn on does not adapt.
    static let onWhite = Color(dsRGB: 0x101720)

    /// Body copy on `slab`.
    static let onSlab = adaptive(light: 0x101720, dark: 0xE7F0F8)

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

    /// The accent, on `slab`. It was its own value because the slab was navy in both
    /// appearances and neither half of `deep` suited it. The slab is a card now and follows
    /// the appearance, so the accent that belongs on a card is the accent.
    static let onSlabAccent = deep

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

    /// The ladder on `slab`.
    ///
    /// This used to be a second set of values at full saturation, because the slab was navy in
    /// both appearances and the light-mode tier colours — drawn for text on white — vanished
    /// on it. The slab is a card now, so there is one ladder: teal, green, amber, red, each
    /// resolving against the appearance the card is in. The name stays so the call sites keep
    /// saying which ground they are on, and the day the two diverge again there is somewhere
    /// for it to happen.
    static func tierVivid(_ rung: RegretTier) -> Color { tier(rung) }

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
    /// The parameter is `rung` because `tier` is a name this type already uses. `isOnSlab`
    /// went with the dark panel: there is one ground now, so there is one answer.
    static func costTint(_ rung: RegretTier) -> Color {
        // Two colours for two meanings, and neither of them grey.
        //
        // Lossless was `.secondary`, which was right for an eyebrow and is wrong for a badge:
        // a grey pill beside a teal rail reads as *disabled*, and "costs nothing" is the good
        // news on this screen. Not the rung's own colour either — that would only repeat what
        // the rail already says. The badge carries the binary the rail does not: free, or
        // yours to judge.
        rung.isLossless ? tier(.inferiorCopy) : tier(.burstLeftover)
    }

    /// The muting neutral, at a value that reads on the slab. It is the most load-bearing
    /// colour in the deletion instrument, because it is what says "in Recently Deleted: gone
    /// from the library, not yours again yet".
    static let neutralOnSlab = adaptive(light: 0x9FAFC1, dark: 0x5D7288)

    /// Secondary copy on the slab.
    static let onSlabMuted = adaptive(light: 0x64768A, dark: 0x8FA3B8)

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
/// A tinted pill: a state, said in one or two words, in the colour of the thing it is about.
///
/// The regret ladder's cost was an eyebrow — small, uppercase, letter-spaced — stacked under
/// the rung's title. An eyebrow is a label *for* what follows it; "costs nothing" is not a
/// label for a list of files, it is a fact about them, and a fact reads faster as a badge than
/// as a caption. The tint is the rung's own colour, so the ladder is legible at a glance down
/// the screen without reading a word of it.
struct Badge: View {

    private let text: String
    private let tint: Color

    init(_ text: String, tint: Color) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.14)))
            .fixedSize(horizontal: false, vertical: true)
    }
}

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

    /// The block that carries the product: a reading and the control that moves it, on a card
    /// lifted off the page.
    ///
    /// It was a dark instrument panel. Three of them, on three adjacent screens, on a pale
    /// page — and the weight was not doing the work the argument for it claimed. What it did
    /// do was force `colorScheme` to dark for everything inside, which meant the regret ladder
    /// had to exist twice over: `tier` drawn for text on white and never used on white, and
    /// `tierVivid` for navy. Retiring the panel collapsed that, and the depth it was providing
    /// is now what actually provides depth on a card: a background step, a hairline, a shadow.
    ///
    /// This was three byte-identical copies of the same eight lines, in the three files that
    /// draw the product's three main blocks. The material that says "this is the instrument,
    /// not another section" is exactly the thing that must not be re-typed per screen.
    /// `radius` because a slab nested inside another rounded thing has to be concentric with
    /// it. The instrument that draws a deletion sits inside the dock, whose corner is
    /// `DS.controlCorner`, and a `slabCorner` block in a `controlCorner` well reads as a
    /// mistake.
    func dsSlab(padding: CGFloat = DS.Space.xl, radius: CGFloat = DS.slabCorner) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(DS.slabFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.slabEdge, lineWidth: 1)
            )
            // A card needs all three to have a boundary: the step off the page above, this
            // hairline, and a shadow. Kept under twelve per cent — heavier than that and a
            // card stops resting on the page and starts hovering over it.
            .shadow(color: .black.opacity(0.07), radius: 18, y: 6)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
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

    /// The quiet key on the instrument panel.
    ///
    /// `keyQuiet` is a pale well carrying `DS.deep`. On the card that is now the right pair,
    /// but the well has to be a tint of the accent rather than of the page, or it disappears
    /// into a white slab.
    static var keyOnSlab: KeyButtonStyle {
        KeyButtonStyle(fill: AnyShapeStyle(DS.deep.opacity(0.10)), foreground: DS.onSlabAccent)
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
        onSlab ? DS.groove : DS.well
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
    /// Wide enough to read as a thing you take hold of.
    ///
    /// It was seven points. Twice, on two different screens, the first thing anyone said about
    /// this control was that there was a stray line on it — once for the depth marker at the
    /// far left, once for the cap itself parked at the far right. A seven-point white sliver on
    /// a sixteen-point track is a scratch, whatever it was meant to be, and when the reader
    /// keeps reading it as a scratch the reader is right.
    private let gripWidth: CGFloat = 18
    private let gripHeight: CGFloat = 30
    /// The control is 30pt of paint in a 44pt target.
    private let hitHeight: CGFloat = 44

    private var span: Double { max(range.upperBound - range.lowerBound, 1) }

    /// False when the depth setting can reach nothing, so there is no target to set.
    ///
    /// A live-looking white handle on a track where every rung is off the table is the control
    /// inviting a drag it will not honour. Greyed and unlit, it reads as what it is.
    private var isLive: Bool { limitFraction > 0 }

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

            // The cap travels the track inset by its own width, and the fill ends at the cap's
            // centre. One derives from the other, so they cannot disagree — and the cap is
            // always wholly inside the groove, never half-overhanging an end, which is the
            // other half of why it read as a sliver rather than as a handle.
            let travel = max(width - gripWidth, 1)
            let capX = travel * CGFloat(fraction)
            let fillWidth = capX + gripWidth / 2

            ZStack(alignment: .leading) {
                // The ladder is the track, and the target lights it up rather than painting
                // over it.
                //
                // The fill used to be an opaque brand capsule laid on top, which meant the one
                // thing this control exists to say — which rung your target reaches into —
                // disappeared the moment the target got large. And the card opens at the app's
                // own suggestion, which in a typical library is most of the bar: the screenshot
                // showed a plain blue-to-cyan gradient with no rung visible anywhere on it.
                // Now the rung colours are always on the track, dimmed past the target, and the
                // brand runs as a thin line under them so the reading still has an owner.
                ladder(in: width)
                    .frame(height: trackHeight)
                    .opacity(0.3)
                    .clipShape(Capsule(style: .continuous))

                ladder(in: width)
                    .frame(height: trackHeight)
                    .clipShape(Capsule(style: .continuous))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: fillWidth)
                    }

                // A plain brand capsule for a track with no ladder on it — the fader is used
                // for one thing that has rungs and nothing that does not, but an empty `rungs`
                // must still draw a fill rather than an empty groove.
                if rungs.isEmpty {
                    Capsule(style: .continuous)
                        .fill(DS.brandRow)
                        .frame(width: fillWidth, height: trackHeight)
                }

                // Where the depth setting stops. Everything past it is space this plan will
                // not take however far the target is dragged.
                //
                // Not at either end. At zero it sat on top of the track's own left cap and
                // read as a stray scratch on the control; at one it marks the end of a track
                // that already ends there. A marker has to have something on both sides of it
                // to be marking anything.
                if limitFraction > 0.02, limitFraction < 0.98 {
                    Rectangle()
                        .fill(DS.onSlab.opacity(0.45))
                        .frame(width: 2, height: trackHeight)
                        .offset(x: width * limitFraction - 1)
                }

                // A fader cap: white, lifted off the track, with the two ridges a real one has.
                // The ridges are what stop an eighteen-point white rectangle from reading as a
                // blank tile — they say which way it slides.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isLive ? Color.white : DS.neutralOnSlab)
                    .overlay(
                        HStack(spacing: 3) {
                            Capsule().frame(width: 1.5)
                            Capsule().frame(width: 1.5)
                        }
                        .frame(height: gripHeight * 0.36)
                        .foregroundStyle(DS.onWhite.opacity(isLive ? 0.28 : 0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(DS.onWhite.opacity(0.28), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(isLive ? 0.28 : 0), radius: 4, y: 1)
                    .frame(width: gripWidth, height: gripHeight)
                    .offset(x: capX)
            }
            .frame(height: hitHeight)
            .contentShape(Rectangle())
            // Anywhere on the track, not only on the grip. The cap is a proper handle now,
            // but a fader you have to hit exactly is still a worse fader.
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

    /// The ladder, drawn twice: dimmed for the whole track, then again at full strength and
    /// masked to the target. So the rung colours are on the control at every value, and the
    /// target reads as how far along the ladder the brightness reaches.
    ///
    /// Normalised to `span`, the same denominator the fill uses — not to the sum of the rungs.
    /// The two are only equal when every rung is present and they add up exactly to the range,
    /// and a rung worth nothing is dropped before this ever sees it. Any other denominator and
    /// the fill stops somewhere the colours say a different rung begins, which is the one thing
    /// this control exists to say. The trailing rectangle takes up whatever is left.
    ///
    /// Rungs past the depth limit lose their hue entirely rather than being faded: they become
    /// the groove they are drawn in.
    ///
    /// They were `color.opacity(0.3)`, and a warm hue killed to a third over a navy slab is
    /// mud — measured off the screenshot, amber `#F5B944` came out `#6A5F40`, an olive nobody
    /// chose. Worse, in the state where the depth setting can reach *nothing*, every rung is
    /// beyond the limit, so the whole control was one olive bar with a grey tick at its left
    /// end: a graphic that reads as broken rather than as "none of this is on offer".
    ///
    /// A hue at low alpha still claims to be a colour. A slate groove claims to be a groove,
    /// which is what an unavailable stretch of track is.
    private func ladder(in width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(laidOutRungs, id: \.rung.id) { entry in
                Rectangle()
                    .fill(entry.isBeyondLimit ? DS.groove : entry.rung.color)
                    .frame(width: max(width * entry.share, 2))
            }
            Rectangle().fill(DS.groove)
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
