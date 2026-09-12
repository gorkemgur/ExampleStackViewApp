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

            VStack(alignment: .leading, spacing: 14) {
                if let title {
                    HStack(spacing: 8) {
                        if let symbolName {
                            Image(systemName: symbolName)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(rail ?? DS.aqua)
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill((rail ?? DS.aqua).opacity(0.14))
                                )
                        }
                        Text(title)
                            .font(.footnote.weight(.semibold))
                            .kerning(0.2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(identifier ?? "")
                        Spacer(minLength: 0)
                    }
                }

                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
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
