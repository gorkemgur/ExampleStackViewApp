import SwiftUI
import DupeCore

/// The weight nobody can account for, said out loud.
///
/// A Live Photo is a still plus about three seconds of video. A RAW+JPEG asset is one entry in
/// Photos holding two photographs. Both are ordinary, both are invisible, and on a phone full of
/// ProRAW shots the second halves can be most of the library.
///
/// **And nothing can remove them.** `PHAssetChangeRequest` has no request that deletes one
/// resource of an asset, and Apple's own developer forum carries a long thread reporting that
/// even recreating a RAW+JPEG asset does not work. So this card does not offer a button. It is
/// here because the number is real, Settings will not break it down, Photos will not mention it,
/// and a person who learns that a quarter of their library is Live Photo video can decide to
/// stop taking them — which is a saving no cleaner can hand them.
///
/// A card that says "you cannot have this back" has to earn its place, so it appears only when
/// there is something to report and it says what to do instead rather than only what cannot be
/// done.
struct SecondResourcesCardView: View {

    let resources: SecondResources

    var body: some View {
        Card(
            "Carried, and not removable",
            symbolName: "square.stack.3d.down.right",
            identifier: "second.title",
            rail: DS.neutral
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Readout.bytes(resources.totalBytes, scale: .title2, unitScale: .footnote, tint: DS.neutral)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("second.total")

                if resources.livePhotoCount > 0 {
                    line(
                        "\(ByteFormatting.string(resources.livePhotoVideoBytes)) of Live Photo video, across \(Counting.items(resources.livePhotoCount)).",
                        identifier: "second.live"
                    )
                }

                if resources.rawCount > 0 {
                    line(
                        "\(ByteFormatting.string(resources.rawBytes)) of RAW, across \(Counting.items(resources.rawCount)) that also hold a JPEG.",
                        identifier: "second.raw"
                    )
                }

                Text("iOS gives no app a way to delete half of an asset, so this is not space DupeSpace can free — it is space worth knowing about. Turning Live Photos off in Camera, or shooting JPEG rather than ProRAW, stops it growing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("second.explain")
            }
        }
    }

    @ViewBuilder
    private func line(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}
