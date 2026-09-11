import CryptoKit
import Foundation
import Photos
import UIKit
import DupeCore

/// Reads pixel data out of the photo library for the scan.
///
/// Every request here sets `isNetworkAccessAllowed = false`. An asset whose original only
/// exists in iCloud is reported as such rather than downloaded: pulling a library down over
/// cellular to look for duplicates would cost the user more than the duplicates ever did.
final class PhotoKitAssetAnalyzer: AssetAnalyzing {

    /// `PHPhotosErrorNetworkAccessRequired`. Spelled as its raw value so the mapping does not
    /// depend on a symbol's availability window.
    private static let networkAccessRequiredCode = 3164

    func contentDigest(for item: MediaItem) async -> ContentDigestResult {
        guard let asset = Self.asset(for: item.id) else { return .unavailable }

        let resources = PHAssetResource.assetResources(for: asset)
        guard
            let resource = resources.first(where: { $0.type == .photo || $0.type == .video })
                ?? resources.first
        else {
            return .unavailable
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        let accumulator = DigestAccumulator()

        return await withCheckedContinuation { continuation in
            let resumeGuard = ResumeGuard()

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    accumulator.update(data)
                },
                completionHandler: { error in
                    guard resumeGuard.claim() else { return }
                    if let error {
                        continuation.resume(returning: Self.classify(error))
                    } else {
                        continuation.resume(returning: .digest(accumulator.finalize()))
                    }
                }
            )
        }
    }

    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
        guard let asset = Self.asset(for: item.id) else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .exact
        options.isSynchronous = false
        options.version = .current

        let side = CGFloat(GrayImageRenderer.renderSize)

        let image: UIImage? = await withCheckedContinuation { continuation in
            let resumeGuard = ResumeGuard()

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                // fastFormat delivers a single result, but the guard makes that a property of
                // this code rather than an assumption about PhotoKit.
                guard resumeGuard.claim() else { return }
                continuation.resume(returning: image)
            }
        }

        guard
            let cgImage = image?.cgImage,
            let gray = GrayImageRenderer.render(cgImage)
        else {
            return nil
        }

        return PerceptualHashes(
            dHash: PerceptualHasher.dHash(gray),
            pHash: PerceptualHasher.pHash(gray)
        )
    }

    // MARK: - Helpers

    private static func asset(for localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    private static func classify(_ error: Error) -> ContentDigestResult {
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain && nsError.code == networkAccessRequiredCode {
            return .cloudOnly
        }
        return .unavailable
    }
}

/// Hashes a resource as it streams in, so a multi-gigabyte video never lands in memory.
private final class DigestAccumulator: @unchecked Sendable {

    private let lock = NSLock()
    private var hasher = SHA256()

    func update(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        hasher.update(data: data)
    }

    func finalize() -> ContentDigest {
        lock.lock(); defer { lock.unlock() }
        return ContentDigest(bytes: Array(hasher.finalize()))
    }
}

/// Makes "resume exactly once" enforceable — resuming a continuation twice traps.
private final class ResumeGuard: @unchecked Sendable {

    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
