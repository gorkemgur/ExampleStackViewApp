import Foundation
import DupeCore

/// A deterministic stand-in for the photo library.
///
/// UI tests need a library that is the same on every run and on every runner image, and they
/// must not trip the system permission alert — a CI machine has nobody to tap it. The fixture
/// is also what SwiftUI previews render against.
final class StubMediaLibrary: MediaLibrary {

    private let access: LibraryAccess
    private let items: [MediaItem]
    private let delay: Duration

    init(access: LibraryAccess, items: [MediaItem], delay: Duration = .zero) {
        self.access = access
        self.items = items
        self.delay = delay
    }

    func currentAccess() -> LibraryAccess { access }

    func requestAccess() async -> LibraryAccess { access }

    func loadInventory() async throws -> [MediaItem] {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        // Mirrors the real library: without full access there is nothing to hand back.
        guard access == .authorized else { return [] }
        return items
    }

    // MARK: - Fixtures

    static func uiTestFixture() -> StubMediaLibrary {
        StubMediaLibrary(access: .authorized, items: sampleItems())
    }

    static func previewFixture(access: LibraryAccess = .authorized) -> StubMediaLibrary {
        StubMediaLibrary(access: access, items: sampleItems())
    }

    /// A small library with the shapes that matter: a big video, a burst, a re-encoded resend,
    /// a pile of screenshots, a Live Photo, and a favourite that must never be touched.
    static func sampleItems() -> [MediaItem] {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        var items: [MediaItem] = []

        items.append(
            MediaItem(
                id: "video-holiday",
                source: .photoLibrary,
                kind: .video,
                displayName: "IMG_4021.MOV",
                byteSize: 1_840_000_000,
                pixelWidth: 3840,
                pixelHeight: 2160,
                duration: 312,
                creationDate: now - 30 * day,
                hasLocationMetadata: true
            )
        )

        items.append(
            MediaItem(
                id: "video-holiday-copy",
                source: .photoLibrary,
                kind: .video,
                displayName: "IMG_4021 (1).MOV",
                byteSize: 1_840_000_000,
                pixelWidth: 3840,
                pixelHeight: 2160,
                duration: 312,
                creationDate: now - 12 * day
            )
        )

        items.append(
            MediaItem(
                id: "video-trip",
                source: .photoLibrary,
                kind: .video,
                displayName: "IMG_3877.MOV",
                byteSize: 620_000_000,
                pixelWidth: 1920,
                pixelHeight: 1080,
                duration: 95,
                creationDate: now - 48 * day,
                hasLocationMetadata: true
            )
        )

        items.append(
            MediaItem(
                id: "video-trip-sent",
                source: .photoLibrary,
                kind: .video,
                displayName: "VID-20240501-WA0003.mp4",
                byteSize: 180_000_000,
                pixelWidth: 1280,
                pixelHeight: 720,
                duration: 95.2,
                creationDate: now - 47 * day,
                isUserLibraryOriginal: false
            )
        )

        items.append(
            MediaItem(
                id: "photo-cliff",
                source: .photoLibrary,
                kind: .image,
                displayName: "IMG_3311.HEIC",
                byteSize: 5_400_000,
                pixelWidth: 4032,
                pixelHeight: 3024,
                creationDate: now - 60 * day,
                isFavorite: true,
                albumCount: 1,
                hasLocationMetadata: true
            )
        )

        items.append(
            MediaItem(
                id: "photo-cliff-resend",
                source: .photoLibrary,
                kind: .image,
                displayName: "IMG-20240612-WA0007.jpg",
                byteSize: 410_000,
                pixelWidth: 1280,
                pixelHeight: 960,
                creationDate: now - 58 * day,
                isUserLibraryOriginal: false
            )
        )

        for index in 0..<6 {
            items.append(
                MediaItem(
                    id: "burst-\(index)",
                    source: .photoLibrary,
                    kind: .image,
                    displayName: "IMG_3980_\(index).HEIC",
                    byteSize: 4_100_000 + Int64(index) * 7_000,
                    pixelWidth: 4032,
                    pixelHeight: 3024,
                    creationDate: now - 21 * day,
                    burstIdentifier: "burst-set-A"
                )
            )
        }

        for index in 0..<14 {
            items.append(
                MediaItem(
                    id: "screenshot-\(index)",
                    source: .photoLibrary,
                    kind: .image,
                    displayName: "IMG_\(2000 + index).PNG",
                    byteSize: 2_300_000 + Int64(index) * 40_000,
                    pixelWidth: 1179,
                    pixelHeight: 2556,
                    creationDate: now - Double(index * 9) * day,
                    isScreenshot: true
                )
            )
        }

        items.append(
            MediaItem(
                id: "live-dinner",
                source: .photoLibrary,
                kind: .image,
                displayName: "IMG_3702.HEIC",
                byteSize: 2_100_000,
                pairedVideoByteSize: 4_800_000,
                pixelWidth: 4032,
                pixelHeight: 3024,
                creationDate: now - 5 * day,
                isLivePhoto: true
            )
        )

        items.append(
            MediaItem(
                id: "photo-cloud-only",
                source: .photoLibrary,
                kind: .image,
                displayName: "IMG_0912.HEIC",
                byteSize: 6_900_000,
                pixelWidth: 4032,
                pixelHeight: 3024,
                creationDate: now - 400 * day,
                isLocallyAvailable: false
            )
        )

        return items
    }
}
