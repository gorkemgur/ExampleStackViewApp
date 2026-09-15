import XCTest
import SwiftUI
import DupeCore
@testable import DupeSpace

/// The palette, held to the two things it claims about itself.
///
/// Nothing pinned these before. `DS`'s own documentation argues at length that one hue means
/// one thing and that the neutrals are chosen rather than `systemGray` — and both claims had
/// drifted, silently, because a colour is a number nobody reads back. These tests read them
/// back.
///
/// The measurements are CIELAB hue angle and WCAG relative luminance, not opinion: "these two
/// reds are hard to tell apart" is a sentence, "their hue angles are 4.4 degrees apart" is a
/// fact that fails a build.
final class PaletteTests: XCTestCase {

    // MARK: - Reading a colour back

    private func components(_ color: Color, _ style: UIUserInterfaceStyle) -> (r: Double, g: Double, b: Double) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    private func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// WCAG relative luminance.
    private func luminance(_ color: Color, _ style: UIUserInterfaceStyle) -> Double {
        let (r, g, b) = components(color, style)
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let first = luminance(a, style), second = luminance(b, style)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// CIELAB, D65. Hue angle is what says whether two colours *mean* the same thing —
    /// lightness and saturation are how loudly they say it.
    private func lab(_ color: Color, _ style: UIUserInterfaceStyle) -> (l: Double, a: Double, b: Double) {
        let (red, green, blue) = components(color, style)
        let r = linear(red), g = linear(green), bl = linear(blue)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * bl) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * bl
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * bl) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3.0) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    private func hueAngle(_ color: Color, _ style: UIUserInterfaceStyle) -> Double {
        let value = lab(color, style)
        return (atan2(value.b, value.a) * 180 / .pi).truncatingRemainder(dividingBy: 360)
    }

    /// The short way round the wheel: 350° and 10° are twenty degrees apart, not three hundred.
    private func hueSeparation(_ first: Color, _ second: Color, _ style: UIUserInterfaceStyle) -> Double {
        let gap = abs(hueAngle(first, style) - hueAngle(second, style))
            .truncatingRemainder(dividingBy: 360)
        return min(gap, 360 - gap)
    }

    private let appearances: [(UIUserInterfaceStyle, String)] = [(.light, "light"), (.dark, "dark")]

    // MARK: - One hue, one meaning

    /// The claim `DS` makes in its own doc comment, enforced.
    ///
    /// `destructive` is the colour of something that cannot be undone. `tier(.similar)` means
    /// "your call, one by one" — a judgement, not a danger. They were 2.0° apart in light and
    /// 4.4° in dark: the same hue at two saturations, which is a difference a reader has to
    /// work out rather than see.
    func testTheJudgementTierIsNotTheDestructiveRed() {
        for (style, name) in appearances {
            XCTAssertGreaterThanOrEqual(
                hueSeparation(DS.tier(.similar), DS.destructive, style),
                40,
                "in \(name), the ladder's top rung and the delete key are the same hue — "
                + "one means 'your call' and the other means 'gone forever'"
            )
        }
    }

    /// The other three rungs are not red either, and none of them collides with its neighbour.
    func testEveryRungOfTheLadderIsItsOwnHue() {
        for (style, name) in appearances {
            for rung in RegretTier.allCases {
                XCTAssertGreaterThanOrEqual(
                    hueSeparation(DS.tier(rung), DS.destructive, style),
                    40,
                    "in \(name), \(rung) shares the destructive red"
                )
            }
            for (first, second) in zip(RegretTier.allCases, RegretTier.allCases.dropFirst()) {
                XCTAssertGreaterThanOrEqual(
                    hueSeparation(DS.tier(first), DS.tier(second), style),
                    20,
                    "in \(name), \(first) and \(second) are adjacent rungs in nearly one hue"
                )
            }
        }
    }

    // MARK: - A ground, not a void

    /// The page is a dark colour, not the absence of one.
    ///
    /// `DS.ink` was `#080C11` — L\* 3.21, where black is 0. The scan screen is one card on it,
    /// and on a real phone that reads as a card floating in nothing.
    func testTheDarkGroundIsNotEffectivelyBlack() {
        XCTAssertGreaterThanOrEqual(
            lab(DS.ink, .dark).l, 9,
            "the page is within a few points of pure black; the app reads as a void with cards on it"
        )
    }

    /// And it is a *chosen* neutral. The file's own argument for the palette is that the
    /// neutrals carry a blue bias so they do not read as `systemGray` — a claim that a
    /// near-black cannot keep, because there is no room left in it for a hue.
    func testTheDarkNeutralsKeepTheirBlueBias() {
        for token in [DS.ink, DS.well, DS.inkRaised, DS.slab] {
            let value = lab(token, .dark)
            XCTAssertGreaterThanOrEqual(
                sqrt(value.a * value.a + value.b * value.b), 6,
                "a ground neutral has lost its bias and is a plain grey"
            )
        }
    }

    /// Raising the page without raising the card would flatten the one thing that makes a card
    /// a card.
    func testTheCardStillLiftsOffThePage() {
        XCTAssertGreaterThan(
            luminance(DS.slab, .dark), luminance(DS.ink, .dark),
            "the card must sit above the page it is on"
        )
        XCTAssertGreaterThanOrEqual(
            contrast(DS.slab, DS.ink, .dark), 1.15,
            "the step from page to card has gone; the hairline and the shadow are carrying it alone"
        )
    }

    // MARK: - Still readable

    /// The cost of lightening a ground is paid by everything written on it. These are the
    /// thresholds that must survive it: 4.5 for copy, 3.0 for a UI element carrying meaning.
    func testEverythingOnACardStaysReadable() {
        for (style, name) in appearances {
            XCTAssertGreaterThanOrEqual(contrast(DS.onSlab, DS.slab, style), 7, "body copy, \(name)")
            XCTAssertGreaterThanOrEqual(contrast(DS.onSlabMuted, DS.slab, style), 4.5, "secondary copy, \(name)")
            XCTAssertGreaterThanOrEqual(contrast(DS.deep, DS.slab, style), 4.5, "the accent, \(name)")
            XCTAssertGreaterThanOrEqual(
                contrast(DS.neutralOnSlab, DS.slab, style), 3,
                "the muting neutral, \(name) — it is what says 'in Recently Deleted', "
                + "which is the most load-bearing thing the deletion instrument draws"
            )
            for rung in RegretTier.allCases {
                XCTAssertGreaterThanOrEqual(
                    contrast(DS.tier(rung), DS.slab, style), 3,
                    "\(rung)'s rail on a card, \(name)"
                )
            }
        }
    }

    // MARK: - A mark drawn on somebody's photograph

    /// What a translucent colour actually becomes once something is drawn behind it.
    ///
    /// Every other token here can be read straight off, because every other token is opaque.
    /// `DS.onPicture` is not: the number that decides whether the badge is readable is the
    /// composite, and the composite depends on the frame behind it — which, on a thumbnail,
    /// is anything at all. So these tests take the two ends of "anything".
    private func composited(_ color: Color, over backdrop: Double) -> Color {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func mix(_ channel: CGFloat) -> Double { Double(channel) * Double(a) + backdrop * (1 - Double(a)) }
        return Color(red: mix(r), green: mix(g), blue: mix(b))
    }

    /// The bright end: a white sky, which is where a translucent dark disc is thinnest.
    func testTheKindBadgeStaysReadableOnTheBrightestFrameThereIs() {
        XCTAssertGreaterThanOrEqual(
            contrast(.white, composited(DS.onPicture, over: 1), .light), 3,
            "the white glyph on the kind badge has gone soft against a white sky — this is the "
            + "one case a dark ground cannot lose, because there is nothing else carrying it"
        )
    }

    /// The dark end: a night frame, where the ground *is* the frame and only the ring is left.
    func testTheKindBadgeKeepsAnEdgeOnTheDarkestFrameThereIs() {
        XCTAssertGreaterThanOrEqual(
            contrast(composited(DS.onPictureEdge, over: 0), .black, .light), 3,
            "on a night frame the badge's ground is indistinguishable from the picture; "
            + "without the hairline there is no badge, only a floating glyph"
        )
    }

    /// The decision, not the colour: this one does not flip with the appearance.
    ///
    /// Everything else in `DS` is adaptive and the next person to read this file will want to
    /// make this adaptive too. It sits on a photograph, and dark mode says nothing about
    /// whether that photograph is a white sky.
    func testTheMarkOnAPictureIgnoresTheAppearance() {
        for token in [DS.onPicture, DS.onPictureEdge] {
            XCTAssertEqual(
                luminance(token, .light), luminance(token, .dark), accuracy: 0.0001,
                "a mark on a photograph was made to follow the appearance; the frame behind it "
                + "does not follow the appearance"
            )
        }
    }

    // MARK: - The frame a mark can actually land on

    /// Composite a translucent token over an opaque one, in a given appearance.
    ///
    /// The `over: Double` version above answers "what does this become on a white or a black
    /// frame". This one answers "what does this become on the app's own card", which is a
    /// different question with a different answer in each appearance.
    private func composited(_ color: Color, over backdrop: Color, _ style: UIUserInterfaceStyle) -> Color {
        let top = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        let under = UIColor(backdrop).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        var ur: CGFloat = 0, ug: CGFloat = 0, ub: CGFloat = 0, ua: CGFloat = 0
        top.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        under.getRed(&ur, green: &ug, blue: &ub, alpha: &ua)
        func mix(_ over: CGFloat, _ below: CGFloat) -> Double {
            Double(over) * Double(ta) + Double(below) * (1 - Double(ta))
        }
        return Color(red: mix(tr, ur), green: mix(tg, ug), blue: mix(tb, ub))
    }

    /// A two-part mark has to be findable on *every* frame, and the two ends are not the worst
    /// case.
    ///
    /// The existing pair of tests sample a white sky and a night shot, and both pass. Neither
    /// looks at the middle, where a translucent dark ground has gone grey and a white hairline
    /// has gone grey with it — and a mid-grey frame is the commonest frame there is.
    ///
    /// No single colour can clear a floor against every backdrop: whatever it is, some frame
    /// matches it. That is why the mark is two parts, and it is the *pair* that has to hold —
    /// for any frame, either the ground separates from it or the hairline does. That is the
    /// claim, and this is the sweep that makes it one.
    func testAMarkOnAPhotographIsFindableOnEveryFrameItCanLandOn() {
        var worst = (ratio: Double.infinity, frame: 0.0)
        for step in stride(from: 0.0, through: 1.0, by: 1.0 / 64.0) {
            let frame = Color(red: step, green: step, blue: step)
            let ground = contrast(composited(DS.onPicture, over: step), frame, .light)
            let edge = contrast(composited(DS.onPictureEdge, over: step), frame, .light)
            let best = max(ground, edge)
            if best < worst.ratio { worst = (best, step) }
        }
        XCTAssertGreaterThanOrEqual(
            worst.ratio, 3,
            "on a frame at \(Int(worst.frame * 255)) grey, neither the badge's ground "
            + "(\(String(format: "%.2f", worst.ratio)):1 at best) nor its hairline separates "
            + "from the picture — the mark is there and nobody can find it"
        )
    }

    // MARK: - The mark that says which copy survives

    /// The seal carries a white tick and nothing else carries it.
    ///
    /// This is the more meaningful of the two marks on the thumbnail — the kind badge says what
    /// a file is, the seal says which copy lives. Its failure does not even need a bright
    /// photograph: the tick is measured against the seal's own disc.
    func testTheSurvivorSealCarriesItsOwnTick() {
        for (style, name) in appearances {
            XCTAssertGreaterThanOrEqual(
                contrast(.white, DS.onPictureAccent, style), 4.5,
                "in \(name) the seal's tick has dissolved into the seal — and the tick is the "
                + "whole message, the disc is only there to hold it"
            )
        }
    }

    /// The same decision as ``testTheMarkOnAPictureIgnoresTheAppearance``, for the same reason.
    func testTheSurvivorSealIgnoresTheAppearance() {
        XCTAssertEqual(
            luminance(DS.onPictureAccent, .light), luminance(DS.onPictureAccent, .dark),
            accuracy: 0.0001,
            "the survivor seal follows the appearance, and it is drawn on a photograph — "
            + "dark mode says nothing about whether that photograph is a white sky"
        )
    }

    // MARK: - The ladder the scan screen draws to be watched

    /// Every row of the scan ladder is text, and text has a floor.
    ///
    /// The screen exists to say "here is the whole pipeline, in order, so you can watch it".
    /// Four of its six rows were drawn at `DS.onSlab.opacity(0.32)` — 2.06:1 — with their
    /// markers at `.opacity(0.22)`, 1.61:1. A stage nobody can read is not a stage anybody can
    /// watch, and the hierarchy between current and waiting is carried by weight, which costs
    /// no contrast at all.
    func testEveryStageOfTheScanLadderIsReadable() {
        for (style, name) in appearances {
            XCTAssertGreaterThanOrEqual(
                contrast(composited(DS.onSlabWaiting, over: DS.slab, style), DS.slab, style), 4.5,
                "in \(name), a stage that has not started yet is under the floor for text"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(composited(DS.onSlabDone, over: DS.slab, style), DS.slab, style), 4.5,
                "in \(name), a stage that has finished is under the floor for text"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(composited(DS.onSlabWaitingMark, over: DS.slab, style), DS.slab, style), 3,
                "in \(name), the dot beside a waiting stage is under the floor for a UI "
                + "element that carries meaning"
            )
        }
    }

    // MARK: - One hue, one meaning — including the brand's

    /// The brand gradient and the ladder's top rung are drawn on the same screen.
    ///
    /// `brandBottom` was `#32D7EB` and `tier(.identical)` in dark mode was `#32D7EB`: not close,
    /// identical. The progress fill and the colour that means "these are the same file" were
    /// one colour, which is verbatim the defect this file documents killing when `aqua` was
    /// deleted — the dark value came back in through the brand.
    func testTheBrandGradientIsNotTheLaddersTopRung() {
        for (style, name) in appearances {
            XCTAssertGreaterThanOrEqual(
                hueSeparation(DS.brandBottom, DS.tier(.identical), style), 20,
                "in \(name), the brand's own gradient wears the identical rung's colour"
            )
        }
    }

    // MARK: - A filled pill knows what it is filled with

    /// `onTint` is right for the tier palette and wrong for everything else.
    ///
    /// The tier colours are dark in light mode and bright in dark mode, so "which ink" and
    /// "which appearance" give the same answer and `onTint` gets away with asking the second
    /// question. `DS.neutral` is a mid grey in both, and `onTint` puts white on it.
    func testAFilledPillCarriesItsOwnLabelWhateverItIsFilledWith() {
        let fills: [(Color, String)] = [
            (DS.deep, "DS.deep"),
            (DS.neutral, "DS.neutral"),
            (DS.tier(.identical), "the identical rung"),
            (DS.tier(.inferiorCopy), "the inferior-copy rung"),
            (DS.tier(.burstLeftover), "the burst rung"),
            (DS.tier(.similar), "the similar rung")
        ]
        for (style, name) in appearances {
            for (fill, label) in fills {
                XCTAssertGreaterThanOrEqual(
                    contrast(DS.onFill(fill, in: style), fill, style), 4.5,
                    "in \(name), a pill filled with \(label) cannot carry its own text"
                )
            }
        }
    }
}

