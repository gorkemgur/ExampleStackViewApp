import SwiftUI

/// Says out loud what this app cannot see.
///
/// Every storage cleaner on the App Store quietly implies it can account for the whole disk.
/// iOS gives no app any view of what another app stores, so claiming otherwise would be a lie
/// the user discovers the moment the numbers do not match Settings.
struct LimitsCardView: View {

    let cloudOnlyBytes: Int64

    var body: some View {
        Card("What this cannot see", symbolName: "questionmark.circle", identifier: "limits.title") {
            VStack(alignment: .leading, spacing: 10) {
                bullet("iOS gives no app a view of what other apps store. WhatsApp, Mail and Messages caches are not counted here — Settings › General › iPhone Storage is the only place that breaks those down.")
                bullet("System files and the OS itself are outside any app's reach.")

                if cloudOnlyBytes > 0 {
                    bullet("\(ByteFormatting.string(cloudOnlyBytes)) of your library has its original in iCloud rather than on this device. Deleting those frees iCloud storage, not local storage.")
                }
            }
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Aligned to the first line's baseline rather than nudged down by a fixed number of
            // points, which drifts the moment the text size changes the line height.
            Circle()
                .fill(Color.secondary)
                .frame(width: 4, height: 4)
                .alignmentGuide(.firstTextBaseline) { dimension in dimension.height }
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
