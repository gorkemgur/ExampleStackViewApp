import Photos
import UIKit

protocol ThumbnailLoading: Sendable {
    func thumbnail(for identifier: String, size: CGSize) async -> UIImage?
}

/// Loads previews from the library without reaching for the network, so a cloud-only item
/// simply has no preview rather than quietly costing the user a download.
final class PhotoKitThumbnailLoader: ThumbnailLoading {

    func thumbnail(for identifier: String, size: CGSize) async -> UIImage? {
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

        let scale = await MainActor.run { UIScreen.main.scale }
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)

        return await withCheckedContinuation { continuation in
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
