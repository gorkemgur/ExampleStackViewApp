import SwiftUI
import UIKit
import DupeCore

/// The app's material: one palette, one type scale, one set of shapes.
///
/// The palette is taken from the icon rather than from the system — `#0A84FF` at the top of the
/// gradient, `#32D7EB` at the bottom — so the Home Screen, the Lock Screen and the app are
/// recognisably the same thing. Everything else is derived from those two hues: the neutrals
/// carry a slight blue bias so they read as chosen rather than as `systemGray`, and the regret
/// ladder gets a cool-to-warm ramp that runs from the aqua end of the brand to a coral, because
/// the one ordering this whole product hangs off is "what does deleting this cost me".
enum DS {

    // MARK: - Ground

    /// The page behind everything.
    static let ink = dynamic(light: 0xEFF3F8, dark: 0x080C11)
    /// A panel lifted off the page.
    static let inkRaised = dynamic(light: 0xFFFFFF, dark: 0x131A22)
    /// A recess: meter tracks, thumbnail wells, anything pressed into the panel.
    static let well = dynamic(light: 0xE2E9F1, dark: 0x0D1319)
    /// The one rule weight in the app.
    static let hairline = dynamic(light: 0xD6E0EA, dark: 0x232D38)
    /// A filled neutral, for the part of a measurement this app cannot act on.
    static let neutral = dynamic(light: 0xA5B4C4, dark: 0x46566A)

    /// The instrument panel: always dark, in either appearance, so the figure on it can carry
    /// the brand gradient at full saturation. Used for the two blocks that are the product —
    /// the invitation to scan, and the space budget.
    static let slab = dynamic(light: 0x0C1B2B, dark: 0x10171F)
    /// Body copy on `slab`.
    static let onSlab = Color(dsRGB: 0xE7F0F8)

    // MARK: - Brand

    /// Text-safe blue. Darker than `#0A84FF` in light mode, where the icon's blue on white is
    /// only just readable at caption sizes.
    static let deep = dynamic(light: 0x0A6FE0, dark: 0x3DA1FF)
    /// Text-safe teal, same reasoning.
    static let aqua = dynamic(light: 0x0C8FA3, dark: 0x32D7EB)

    /// The icon's own two stops. Fills only — never text on a light ground.
    static let brandTop = Color(dsRGB: 0x0A84FF)
    static let brandBottom = Color(dsRGB: 0x32D7EB)

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
        case .identical: return dynamic(light: 0x0C8FA3, dark: 0x32D7EB)
        case .inferiorCopy: return dynamic(light: 0x10805F, dark: 0x3DDC97)
        case .burstLeftover: return dynamic(light: 0x996100, dark: 0xF5B944)
        case .similar: return dynamic(light: 0xBC4127, dark: 0xF2684E)
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

    static let corner: CGFloat = 20
    static let railWidth: CGFloat = 4

    // MARK: - Plumbing

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
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
        tint: Color = DS.aqua
    ) -> Text {
        let formatted = ByteFormatting.string(value)
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
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
    func dsWell(radius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(DS.well)
        )
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
        let configuration: Configuration

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(style.isEnabled ? style.foreground : Color.secondary)
                .frame(maxWidth: style.expands ? .infinity : nil)
                .frame(minHeight: style.height)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(style.isEnabled ? style.fill : AnyShapeStyle(DS.well))
                )
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .opacity(configuration.isPressed ? 0.82 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .animation(Motion.control, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == KeyButtonStyle {

    static var key: KeyButtonStyle { KeyButtonStyle() }

    /// A key that carries a meaning rather than the brand: a tier's colour, or red.
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

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(segment.color.opacity(segment.isMuted ? 0.22 : 1))
                        .frame(width: width(for: segment.value, in: proxy.size.width))
                }
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(DS.well)
            }
        }
        .frame(height: height)
        .animation(Motion.content, value: segments)
    }

    private func width(for value: Double, in available: CGFloat) -> CGFloat {
        guard total > 0, value > 0 else { return 0 }
        let fraction = min(value / total, 1)
        // A hairline for anything real but tiny: "you have 40 MB of duplicates" must not
        // render as nothing at all.
        return max(available * fraction - 2, 3)
    }
}
