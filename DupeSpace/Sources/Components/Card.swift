import SwiftUI

/// The one container every section on the overview screen sits in.
///
/// The accessibility identifier lands on the title text rather than on the container: a
/// SwiftUI stack is not reliably an accessibility element of its own, whereas a `Text` always
/// shows up as a static text, so UI tests can query it without guessing at element types.
///
/// A card may carry a `rail`: a coloured bar down its leading edge that says which regret tier
/// the card is about. That is the only depth cue a panel gets — no drop shadows, because one
/// shadow on every block flattens the hierarchy instead of building one. A hairline separates
/// the panel from the page; the rail says what it is.
struct Card<Content: View>: View {

    private let title: String?
    private let symbolName: String?
    private let identifier: String?
    private let rail: Color?
    private let content: Content

    init(
        _ title: String? = nil,
        symbolName: String? = nil,
        identifier: String? = nil,
        rail: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbolName = symbolName
        self.identifier = identifier
        self.rail = rail
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let rail {
                Capsule(style: .continuous)
                    .fill(rail)
                    .frame(width: DS.railWidth)
            }

            VStack(alignment: .leading, spacing: DS.Space.m) {
                if let title {
                    // No icon chip.
                    //
                    // A tinted rounded square holding an SF Symbol is the single most common
                    // component on the App Store — every settings row, every section header,
                    // in every app. It was also saying nothing the rail beside it does not
                    // already say in the same colour. The glyph stays, inline and unboxed,
                    // where it reads as punctuation rather than as an icon slot.
                    HStack(spacing: 7) {
                        if let symbolName {
                            Image(systemName: symbolName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(rail ?? DS.deep)
                                .imageScale(.small)
                        }
                        // A card title was 13pt, smaller than the 15pt body inside it — a
                        // heading quieter than the thing it heads.
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(identifier ?? "")
                        Spacer(minLength: 0)
                    }
                }

                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.xl)
        .dsPanel()
    }
}

extension View {

    /// Cards settle in as they scroll instead of popping into place.
    ///
    /// Deliberately subtle: this is a screen where people make irreversible decisions, and
    /// motion that draws attention to itself is motion that distracts from the decision. Off
    /// entirely when the system asks for reduced motion.
    func cardEntrance() -> some View {
        modifier(CardEntrance())
    }
}

private struct CardEntrance: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.scrollTransition { view, phase in
                // No blur: a blurred card reads as a rendering fault rather than as content
                // that is scrolled away. Opacity and scale carry the depth on their own.
                view
                    .opacity(phase.isIdentity ? 1 : 0.45)
                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
            }
        }
    }
}
