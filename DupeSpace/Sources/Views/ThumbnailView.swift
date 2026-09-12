import SwiftUI
import DupeCore

/// A preview tile that falls back to a symbol rather than an empty box, because an item with
/// no local preview is usually one deliberately left in iCloud and the UI should say so.
struct ThumbnailView: View {

    let item: MediaItem
    let side: CGFloat
    let loader: any ThumbnailLoading

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.well)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: side * 0.3))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: item.id) {
            guard image == nil else { return }
            image = await loader.thumbnail(for: item.id, size: CGSize(width: side, height: side))
        }
    }

    private var placeholderSymbol: String {
        if !item.isLocallyAvailable { return "icloud" }
        return item.kind == .video ? "film" : "photo"
    }
}
