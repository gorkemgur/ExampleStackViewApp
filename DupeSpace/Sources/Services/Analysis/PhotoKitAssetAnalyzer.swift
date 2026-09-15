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
        //
        // By type alone. The filename used to be the tie-break and part of the hash, and that
        // made this digest an identity rather than a fingerprint of the content: two files
        // with every byte the same and different names came out different. Which is the
        // ordinary case — the same picture saved twice is `IMG_4021.JPG` and `IMG_4021 1.JPG`
        // — so the whole "identical copies, costs nothing" tier could never fire for a
        // photograph. Caught by the real-library job on its first end-to-end run: two
        // byte-identical pairs put into a real Photos library, neither offered.
        let resources = PHAssetResource.assetResources(for: asset)
            .sorted { $0.type.rawValue < $1.type.rawValue }
        guard !resources.isEmpty else { return .unavailable }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        let accumulator = DigestAccumulator()

        for resource in resources {
            // A header per resource so two different splits of the same bytes cannot collide.
            // The *type*, and nothing else: a name is not content.
            accumulator.update(Data("r\(resource.type.rawValue)|".utf8))

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

    /// The fingerprint of a photograph, at four times the size the fingerprint itself is.
    ///
    /// TWO THINGS WERE WRONG HERE, and the real-library job found them by finding nothing: two
    /// photographs put into a library as the same picture at half the size and a third of the
    /// quality were never offered, while the byte-identical pairs and every video pair were.
    ///
    /// The first is the size asked for. This requested `GrayImageRenderer.renderSize` — 64,
    /// which is the size of the *buffer the hash is computed on*. Handing the hasher something
    /// that has already been reduced to 64 across leaves it nothing to average away: whatever
    /// aliasing PhotoKit's own reduction introduced is now the signal. `FileAssetAnalyzer` has
    /// asked for four times the render size since the day it was written, with the reasoning
    /// spelled out next to it, and this file never got the memo.
    ///
    /// The second is worse and had nothing to do with the missing pairs. The matcher compares
    /// every fingerprint against every other in one sweep — photo-library items and folder
    /// items together — and the two halves were reducing pictures with two different
    /// downsamplers at two different sizes. The same photograph, once in Photos and once in a
    /// folder you handed over, could fail to match itself. So when PhotoKit cannot supply
    /// something hashable, this falls back to reading the original resource and decoding it
    /// with the same ImageIO path the folder half uses, and the two halves meet.
    func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? {
        guard let asset = Self.asset(for: item.id) else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .exact
        options.isSynchronous = false
        options.version = .current

        let side = CGFloat(GrayImageRenderer.renderSize * 4)

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

        if let cgImage = image?.cgImage, let gray = GrayImageRenderer.render(cgImage) {
            return PerceptualHashes(
                dHash: PerceptualHasher.dHash(gray),
                pHash: PerceptualHasher.pHash(gray)
            )
        }

        return await Self.hashesFromTheOriginal(of: asset)
    }

    /// When `PHImageManager` returns nothing this code can hash.
    ///
    /// It returns `nil` for an asset whose rendition is not available locally, and a `UIImage`
    /// with no `cgImage` behind it for some others. Either way the previous version of this
    /// gave up and the scan simply never learned that photograph's fingerprint — silently, and
    /// indistinguishably from a picture that genuinely matched nothing.
    ///
    /// Reading the original resource is more expensive than a cached thumbnail, which is why
    /// it is the fallback and not the path. Nothing is downloaded: the same
    /// `isNetworkAccessAllowed = false` applies, and a cloud-only original fails here too —
    /// correctly, because the scan set those aside before it ever got this far.
    private static func hashesFromTheOriginal(of asset: PHAsset) async -> PerceptualHashes? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo })
            ?? resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first
        else {
            return nil
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        let collector = ByteCollector()
        let failed: Bool = await withCheckedContinuation { continuation in
            let resumeGuard = ResumeGuard()
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { collector.append($0) },
                completionHandler: { error in
                    guard resumeGuard.claim() else { return }
                    continuation.resume(returning: error != nil)
                }
            )
        }

        guard !failed else { return nil }
        let data = collector.take()
        guard !data.isEmpty else { return nil }
        return FileAssetAnalyzer.hashes(of: data)
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

/// Gathers a resource's bytes as they stream in.
///
/// Bounded by one original photograph, which is the only kind of resource this is used for —
/// the digest path streams into a hasher instead precisely so a video never lands in memory.
private final class ByteCollector: @unchecked Sendable {

    private let lock = NSLock()
    private var bytes = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        bytes.append(chunk)
    }

    func take() -> Data {
        lock.lock(); defer { lock.unlock() }
        return bytes
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
