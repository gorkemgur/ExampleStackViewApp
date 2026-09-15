import Foundation
import Photos
import DupeCore

/// The real library.
///
/// The inventory pass is metadata only: it never requests image data, so it costs no cellular
/// traffic and does not pull anything down from iCloud. Whether an asset's original is
/// actually on the device is therefore not known yet and is resolved later, during the scan,
/// when a resource read either succeeds locally or does not.
final class PhotoKitMediaLibrary: MediaLibrary {

    func currentAccess() -> LibraryAccess {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> LibraryAccess {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    func loadInventory() async throws -> [MediaItem] {
        await Task.detached(priority: .userInitiated) {
            let albumCounts = Self.albumMembershipCounts()

            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let assets = PHAsset.fetchAssets(with: options)
            var items: [MediaItem] = []
            items.reserveCapacity(assets.count)

            assets.enumerateObjects { asset, _, _ in
                items.append(Self.makeItem(asset, albumCounts: albumCounts))
            }
            return items
        }.value
    }

    // MARK: - Mapping

    private static func map(_ status: PHAuthorizationStatus) -> LibraryAccess {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }

    /// One sweep over every user album, rather than a per-asset query. Album membership is a
    /// protection signal, so it has to be known before anything can be proposed for deletion.
    private static func albumMembershipCounts() -> [String: Int] {
        var counts: [String: Int] = [:]

        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        collections.enumerateObjects { collection, _, _ in
            let members = PHAsset.fetchAssets(in: collection, options: nil)
            members.enumerateObjects { asset, _, _ in
                counts[asset.localIdentifier, default: 0] += 1
            }
        }
        return counts
    }

    private static func makeItem(_ asset: PHAsset, albumCounts: [String: Int]) -> MediaItem {
        let resources = PHAssetResource.assetResources(for: asset)

        let primary = resources.first { $0.type == .photo || $0.type == .video } ?? resources.first
        let pairedVideo = resources.first { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo }

        // The RAW half of a RAW+JPEG asset. `primary` picks `.photo`, which is the JPEG, so
        // without this a ProRAW photograph reports the few megabytes of its JPEG and hides the
        // fifty it is actually using. Read here because `assetResources(for:)` has already been
        // fetched — asking again per asset would double the cost of the inventory pass.
        let alternate = resources.first { $0.type == .alternatePhoto }

        // An edit leaves adjustment data and a rendered full-size resource behind.
        let isEdited = resources.contains {
            $0.type == .adjustmentData || $0.type == .fullSizePhoto || $0.type == .fullSizeVideo
        }

        return MediaItem(
            id: asset.localIdentifier,
            source: .photoLibrary,
            kind: asset.mediaType == .video ? .video : .image,
            displayName: primary?.originalFilename ?? asset.localIdentifier,
            byteSize: byteSize(of: primary),
            pairedVideoByteSize: byteSize(of: pairedVideo),
            alternatePhotoByteSize: byteSize(of: alternate),
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            isFavorite: asset.isFavorite,
            albumCount: albumCounts[asset.localIdentifier] ?? 0,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isEdited: isEdited,
            burstIdentifier: asset.burstIdentifier,
            isLocallyAvailable: true,
            hasLocationMetadata: asset.location != nil,
            isUserLibraryOriginal: asset.sourceType.contains(.typeUserLibrary)
        )
    }

    /// `PHAssetResource` exposes its size only through key-value coding. The documented
    /// alternative is to stream the whole resource and count bytes, which would turn an
    /// inventory pass into a full read of the library.
    private static func byteSize(of resource: PHAssetResource?) -> Int64 {
        guard let resource else { return 0 }
        guard let value = resource.value(forKey: "fileSize") as? NSNumber else { return 0 }
        return value.int64Value
    }
}
