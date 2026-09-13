import Foundation
@testable import DupeCore

/// Deterministic RNG so a failure found in CI reproduces locally, byte for byte.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum Fixtures {

    static func image(width: Int, height: Int, _ value: (Int, Int) -> Int) -> GrayImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = UInt8(max(0, min(255, value(x, y))))
            }
        }
        return GrayImage(width: width, height: height, pixels: pixels)!
    }

    /// A smooth diagonal gradient with a couple of bright blobs, so the DCT has real
    /// low-frequency structure to work with rather than a flat field.
    static func scene(width: Int = 256, height: Int = 256, seed: Int = 0) -> GrayImage {
        image(width: width, height: height) { x, y in
            let base = (x * 255 / max(width - 1, 1) + y * 255 / max(height - 1, 1)) / 2
            let blob = ((x - width / 3 + seed) * (x - width / 3 + seed) + (y - height / 3) * (y - height / 3)) < (width * width / 40) ? 70 : 0
            let blob2 = ((x - 2 * width / 3) * (x - 2 * width / 3) + (y - 2 * height / 3) * (y - 2 * height / 3)) < (width * width / 60) ? -60 : 0
            return base + blob + blob2
        }
    }

    static func item(
        _ id: String,
        source: MediaSource = .photoLibrary,
        kind: MediaKind = .image,
        bytes: Int64 = 1_000_000,
        pairedVideoBytes: Int64 = 0,
        alternatePhotoBytes: Int64 = 0,
        width: Int = 4032,
        height: Int = 3024,
        favorite: Bool = false,
        albums: Int = 0,
        screenshot: Bool = false,
        live: Bool = false,
        edited: Bool = false,
        local: Bool = true,
        location: Bool = false,
        created: Date? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            source: source,
            kind: kind,
            displayName: id,
            byteSize: bytes,
            pairedVideoByteSize: pairedVideoBytes,
            alternatePhotoByteSize: alternatePhotoBytes,
            pixelWidth: width,
            pixelHeight: height,
            duration: kind == .video ? 12 : 0,
            creationDate: created,
            isFavorite: favorite,
            albumCount: albums,
            isScreenshot: screenshot,
            isLivePhoto: live,
            isEdited: edited,
            isLocallyAvailable: local,
            hasLocationMetadata: location
        )
    }

    static func index(_ items: [MediaItem]) -> [String: MediaItem] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
}
