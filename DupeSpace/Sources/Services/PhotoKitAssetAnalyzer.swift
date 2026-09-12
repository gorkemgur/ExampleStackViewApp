import AVFoundation
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

        // Every resource, in a fixed order: the original, any adjustment data, the rendered
        // edit, a Live Photo's paired movie. Hashing only the first would report two photos
        // as byte-identical when one of them carries edits the other does not — and that
        // equality is exactly what promotes a pair to the tier labelled "loses nothing".
        let resources = PHAssetResource.assetResources(for: asset).sorted {
            $0.type.rawValue == $1.type.rawValue
                ? $0.originalFilename < $1.originalFilename
                : $0.type.rawValue < $1.type.rawValue
        }
        guard !resources.isEmpty else { return .unavailable }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        let accumulator = DigestAccumulator()

        for resource in resources {
            // A header per resource so two different splits of the same bytes cannot collide.
            accumulator.update(Data("r\(resource.type.rawValue):\(resource.originalFilename)|".utf8))

            if let error = await Self.append(resource, to: accumulator, options: options) {
                return Self.classify(error)
            }
        }

        return .digest(accumulator.finalize())
    }

    private static func append(
        _ resource: PHAssetResource,
        to accumulator: DigestAccumulator,
        options: PHAssetResourceRequestOptions
    ) async -> Error? {
        await withCheckedContinuation { continuation in
            let resumeGuard = ResumeGuard()

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    accumulator.update(data)
                },
                completionHandler: { error in
                    guard resumeGuard.claim() else { return }
                    continuation.resume(returning: error)
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

    func videoSignature(for item: MediaItem) async -> VideoSignature? {
        guard item.kind == .video, item.isLocallyAvailable else { return nil }
        guard let asset = Self.asset(for: item.id) else { return nil }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        options.version = .current

        let video: AVAsset? = await withCheckedContinuation { continuation in
            let resumeGuard = ResumeGuard()
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { video, _, _ in
                guard resumeGuard.claim() else { return }
                continuation.resume(returning: video)
            }
        }

        guard let video else { return nil }
        return await VideoFrameSampler.signature(for: video)
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
