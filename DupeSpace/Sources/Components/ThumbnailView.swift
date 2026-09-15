import SwiftUI
import DupeCore

/// A preview tile that falls back to a symbol rather than an empty box, because an item with
/// no local preview is usually one deliberately left in iCloud and the UI should say so.
struct ThumbnailView: View {

    let item: MediaItem
    let side: CGFloat
    let loader: any ThumbnailLoading

    @State private var image: UIImage?
    @State private var hasAnswered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.well)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if hasAnswered {
                // Only once the loader has actually come back with nothing. While a screenful
                // of rows is still fetching, the same grey box and `photo` glyph that means
                // "this one has no preview" made every row look permanently broken.
                Image(systemName: placeholderSymbol)
                    .font(.system(size: side * 0.3))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: item.id) {
            // No `guard image == nil`. A group's row keeps its SwiftUI identity when the user
            // picks a different survivor — the id is tier plus group, and neither changes — so
            // this view and its `@State` survived while the item under it did not. The task
            // re-fired on the new id, the guard returned immediately, and the row showed the
            // *previous* keeper's picture beside the new keeper's filename, on the screen where
            // the whole question is which picture you are keeping.
            //
            // The loader caches, so clearing and re-asking costs nothing for an image already
            // seen.
            image = nil
            hasAnswered = false
            image = await loader.thumbnail(for: item.id, size: CGSize(width: side, height: side))
            hasAnswered = true
        }
    }

    private var placeholderSymbol: String {
        if !item.isLocallyAvailable { return "icloud" }
        return item.kind == .video ? "film" : "photo"
    }
}
