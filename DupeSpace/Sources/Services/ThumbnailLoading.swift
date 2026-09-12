import Photos
import UIKit

protocol ThumbnailLoading: Sendable {
    func thumbnail(for identifier: String, size: CGSize) async -> UIImage?
}

/// Loads previews from the library without reaching for the network, so a cloud-only item
/// simply has no preview rather than quietly costing the user a download.
final class PhotoKitThumbnailLoader: ThumbnailLoading, @unchecked Sendable {

    /// Previews already fetched, kept so scrolling back up is free.
    ///
    /// This matters now that the review list is genuinely lazy. A lazy stack recycles its
    /// rows, and each row keeps its image in `@State`, which goes with the row — so without a
    /// cache every scroll back up re-fetches from PhotoKit and the whole screen flickers
    /// through placeholders on the way. `NSCache` also releases under memory pressure on its
    /// own, which is the right behaviour for eighty-five thumbnails on a phone.
    private let cache = NSCache<NSString, UIImage>()

    /// Read once, by whoever builds this, rather than per request.
    ///
    /// It used to be `await MainActor.run { UIScreen.main.scale }` inside `thumbnail(for:)` —
    /// a hop to the main actor for every single row, on the screen whose main actor is already
    /// the thing under pressure. `UIScreen.main` is also main-actor isolated and deprecated
    /// under multi-scene, so it belongs at the call site, which is a view.
    private let scale: CGFloat

    init(scale: CGFloat) {
        self.scale = scale
        cache.countLimit = 300
    }

    func thumbnail(for identifier: String, size: CGSize) async -> UIImage? {
        let key = "\(identifier)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        else {
            return nil
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false

        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)

        let image: UIImage? = await withCheckedContinuation { continuation in
            let resumeGuard = ResumeOnce()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: pixelSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                guard resumeGuard.claim() else { return }
                continuation.resume(returning: image)
            }
        }

        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// Paints a stable placeholder derived from the identifier, so previews and UI tests show
/// something recognisable and identical on every run.
final class StubThumbnailLoader: ThumbnailLoading {

    func thumbnail(for identifier: String, size: CGSize) async -> UIImage? {
        let hue = Double(abs(identifier.hashValue) % 360) / 360.0
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(hue: hue, saturation: 0.45, brightness: 0.75, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
