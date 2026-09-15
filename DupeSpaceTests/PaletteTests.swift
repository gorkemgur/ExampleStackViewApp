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
}
