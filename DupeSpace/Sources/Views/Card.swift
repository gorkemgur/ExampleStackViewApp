import SwiftUI

/// The one container every section on the overview screen sits in.
///
/// The accessibility identifier lands on the title text rather than on the container: a
/// SwiftUI stack is not reliably an accessibility element of its own, whereas a `Text` always
/// shows up as a static text, so UI tests can query it without guessing at element types.
struct Card<Content: View>: View {

    private let title: String?
    private let symbolName: String?
    private let identifier: String?
    private let content: Content

    init(
        _ title: String? = nil,
        symbolName: String? = nil,
        identifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbolName = symbolName
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 6) {
                    if let symbolName {
                        Image(systemName: symbolName)
                            .font(.footnote)
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier(identifier ?? "")
                }
                .foregroundStyle(.secondary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
