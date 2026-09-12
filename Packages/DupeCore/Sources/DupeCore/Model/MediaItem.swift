import Foundation

/// What kind of content an item holds.
public enum MediaKind: Int, Sendable, Codable, CaseIterable {
    case image
    case video
    case document
}

/// Where an item was indexed from.
public enum MediaSource: Int, Sendable, Codable, CaseIterable {
    /// PhotoKit asset.
    case photoLibrary
    /// File inside a user-granted, security-scoped folder.
    case fileFolder
}

/// A single indexed item. Deliberately free of PhotoKit / AVFoundation types so every
/// decision that can destroy a user's file is made in code that runs under unit test.
public struct MediaItem: Sendable, Hashable, Identifiable {

    public let id: String
    public let source: MediaSource
    public let kind: MediaKind

    public var displayName: String
    /// Size of the primary resource in bytes. For a photo library asset this is the
    /// *original* size, which may differ from what the device currently stores.
    public var byteSize: Int64
    /// Bytes of the paired Live Photo movie, if any.
    public var pairedVideoByteSize: Int64

    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Seconds. Zero for stills.
    public var duration: Double

    public var creationDate: Date?
    public var modificationDate: Date?

    public var isFavorite: Bool
    /// How many user albums reference this item.
    public var albumCount: Int
    public var isScreenshot: Bool
    public var isLivePhoto: Bool
    /// Has non-destructive edits attached.
    public var isEdited: Bool
    public var burstIdentifier: String?
    /// False when the original only exists in iCloud.
    public var isLocallyAvailable: Bool
    public var hasLocationMetadata: Bool
    /// Captured by this user rather than synced from an external source.
    public var isUserLibraryOriginal: Bool

    public init(
        id: String,
        source: MediaSource,
        kind: MediaKind,
        displayName: String = "",
        byteSize: Int64 = 0,
        pairedVideoByteSize: Int64 = 0,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        duration: Double = 0,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        isFavorite: Bool = false,
        albumCount: Int = 0,
        isScreenshot: Bool = false,
        isLivePhoto: Bool = false,
        isEdited: Bool = false,
        burstIdentifier: String? = nil,
        isLocallyAvailable: Bool = true,
        hasLocationMetadata: Bool = false,
        isUserLibraryOriginal: Bool = true
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.displayName = displayName
        self.byteSize = byteSize
        self.pairedVideoByteSize = pairedVideoByteSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isFavorite = isFavorite
        self.albumCount = albumCount
        self.isScreenshot = isScreenshot
        self.isLivePhoto = isLivePhoto
        self.isEdited = isEdited
        self.burstIdentifier = burstIdentifier
        self.isLocallyAvailable = isLocallyAvailable
        self.hasLocationMetadata = hasLocationMetadata
        self.isUserLibraryOriginal = isUserLibraryOriginal
    }

    /// Every byte the item is responsible for, including the Live Photo movie.
    public var totalByteSize: Int64 { byteSize + pairedVideoByteSize }

    public var pixelCount: Int { pixelWidth * pixelHeight }

    /// True when the user has signalled they care about this item.
    public var isProtected: Bool { isFavorite || albumCount > 0 }

    /// The fingerprinting algorithm's own version, carried in every `contentVersion`.
    ///
    /// Without it the cache answers a question it was never asked. `contentVersion` says "these
    /// bytes have not changed", and the cache reads that as "this stored hash is still the
    /// right answer" — which is only true while the *hasher* has not changed either. Change the
    /// render size, the resample chain or a bit in `pHash`, and every cached record stays
    /// "valid" while the new build compares new hashes against old ones and quietly stops
    /// finding duplicates. Bump this whenever anything upstream of a stored fingerprint moves.
    ///
    /// fp2: the pHash DC term replaced by the (0,8) coefficient.
    public static let fingerprintFormat = "fp2"

    /// Changes whenever the item's bytes could have — or whenever the way this app reads them
    /// has. Cheap to compute from metadata the library already handed over, which is the point:
    /// it decides whether a stored fingerprint can be trusted without opening the file to find
    /// out.
    ///
    /// `isEdited` and `duration` are in here because an adjustment can be applied without
    /// moving `modificationDate` or changing the resource size, and a stale digest is exactly
    /// what promotes a pair into the tier this app labels "loses nothing at all".
    public var contentVersion: String {
        let modified = Int((modificationDate?.timeIntervalSince1970 ?? 0).rounded())
        let seconds = Int(duration.rounded())
        return "\(Self.fingerprintFormat)-\(byteSize)-\(pairedVideoByteSize)-\(pixelWidth)x\(pixelHeight)-\(modified)-\(seconds)-\(isEdited ? 1 : 0)"
    }

    public var aspectRatio: Double {
        guard pixelHeight > 0 else { return 0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }
}
