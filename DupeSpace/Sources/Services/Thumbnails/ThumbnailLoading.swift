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
        // The promise on the scan screen — "nothing is downloaded from iCloud" — is kept, and
        // it is the reason this stays false. What it cost was measured on a real phone: the
        // 52pt and 64pt thumbnails in the list rendered and the 200pt comparison slider in
        // group detail was empty, both halves of it, for every group. Small sizes are served
        // out of PhotoKit's always-local thumbnail pyramid; anything larger is answered from
        // the original, and on a library set to Optimise iPhone Storage the original is not
        // here. `.highQualityFormat` then delivers exactly once, with nothing.
        options.isNetworkAccessAllowed = false
        // `.opportunistic` is the whole fix. It delivers the best *local* rendition first —
        // degraded, instantly, and above all present — instead of holding out for a quality
        // that would need the network and then returning nil. A soft picture of the photograph
        // you are deciding about beats a grey placeholder next to a Delete button.
        //
        // It calls back more than once; `ResumeOnce` already takes the first and drops the
        // rest, which is what makes this a one-line change rather than a rewrite.
        options.deliveryMode = .opportunistic
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
            ) { image, info in
                guard resumeGuard.claim() else { return }
                // The info dictionary was being thrown away, which is why "the photograph is
                // in iCloud" and "the request failed" looked identical from here: both were
                // nil. Logged rather than surfaced — the view's job is to draw something, not
                // to explain PhotoKit — but the next person to see an empty slider gets the
                // reason out of the console instead of out of a week.
                if image == nil {
                    let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                    let failure = info?[PHImageErrorKey] as? NSError
                    Self.log(identifier: identifier, pixelSize: pixelSize, inCloud: inCloud, error: failure)
                }
                continuation.resume(returning: image)
            }
        }

        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private static func log(identifier: String, pixelSize: CGSize, inCloud: Bool, error: NSError?) {
        let reason = inCloud
            ? "the original is in iCloud and downloading is not allowed"
            : (error.map { "\($0.domain) \($0.code)" } ?? "no image and no reason given")
        print(
            "[thumbnail] nothing at \(Int(pixelSize.width))x\(Int(pixelSize.height)) "
            + "for \(identifier.prefix(12)): \(reason)"
        )
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
