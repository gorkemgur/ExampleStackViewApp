import Foundation

/// What a library carries that nobody asked for and nobody can remove.
///
/// Two kinds of asset hold a second resource beside the one you have looked at:
///
///   * a **Live Photo** is a still plus about three seconds of video, and the video is
///     typically three to five times the still;
///   * a **RAW+JPEG** pair is one asset with two pictures in it, and the RAW half of a ProRAW
///     shot is twenty-five to seventy-five megabytes against a few for the JPEG.
///
/// Together they are often the largest thing on an iPhone that nobody can account for, and
/// **iOS offers no way to remove either half.** The RAW is
/// `PHAssetResourceTypeAlternatePhoto` and `PHAssetChangeRequest` has no request that deletes
/// one resource of an asset; Apple's own developer forum carries a long thread reporting that
/// even *recreating* a RAW+JPEG asset through `addResource` does not work. The only route
/// anyone can evidence is export the pair, delete the original, and reimport the half you
/// want — which destroys the person's asset in order to rebuild it, on a path other developers
/// report as broken. This app does not do that, and will not until somebody has proven it on a
/// real device with real photographs.
///
/// So this type exists to *say* the number rather than act on it. That is worth doing on its
/// own: Settings will not break it down, Photos will not mention it, and the space is real. A
/// person who knows a quarter of their library is Live Photo video can decide to stop taking
/// them, which is a saving no cleaner can offer them.
public struct SecondResources: Sendable, Equatable {

    /// Photographs that carry about three seconds of video each.
    public let livePhotoCount: Int
    public let livePhotoVideoBytes: Int64

    /// Photographs that carry a RAW alongside the JPEG.
    public let rawCount: Int
    public let rawBytes: Int64

    public init(
        livePhotoCount: Int = 0,
        livePhotoVideoBytes: Int64 = 0,
        rawCount: Int = 0,
        rawBytes: Int64 = 0
    ) {
        self.livePhotoCount = livePhotoCount
        self.livePhotoVideoBytes = livePhotoVideoBytes
        self.rawCount = rawCount
        self.rawBytes = rawBytes
    }

    public var totalBytes: Int64 { livePhotoVideoBytes + rawBytes }

    /// Nothing to say rather than a row of zeroes. A card that appears on every library and
    /// reads "0 bytes" teaches people to stop reading the screen.
    public var isEmpty: Bool { totalBytes <= 0 }

    /// Counted from the sizes rather than from the flags.
    ///
    /// `isLivePhoto` is set by a media subtype and `pairedVideoByteSize` by a resource that may
    /// not be there — an asset can claim to be a Live Photo while its paired video is not on
    /// this device, and counting it would put a number on screen that nothing backs. Only
    /// resources whose bytes were actually measured are counted.
    public static func tally(_ items: [MediaItem]) -> SecondResources {
        var liveCount = 0
        var liveBytes: Int64 = 0
        var rawCount = 0
        var rawBytes: Int64 = 0

        for item in items {
            if item.pairedVideoByteSize > 0 {
                liveCount += 1
                liveBytes += item.pairedVideoByteSize
            }
            if item.alternatePhotoByteSize > 0 {
                rawCount += 1
                rawBytes += item.alternatePhotoByteSize
            }
        }

        return SecondResources(
            livePhotoCount: liveCount,
            livePhotoVideoBytes: liveBytes,
            rawCount: rawCount,
            rawBytes: rawBytes
        )
    }
}
