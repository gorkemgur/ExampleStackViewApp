import Foundation

/// What a scan is about to do, worked out from metadata alone and before anything is opened.
///
/// This exists because the screen offering the scan was making a promise the pipeline does not
/// keep. It said *only the handful of items that could possibly match ever get read*, which is
/// true of videos and of documents and is simply false of photographs: every image the device
/// holds locally is opened and fingerprinted, because two photographs of the same moment share
/// no byte and no file size, and there is no cheaper way to find them.
///
/// An app whose whole argument is that it shows its reasoning cannot afford a comforting
/// sentence that its own code contradicts eighty lines later. So the screen now states the
/// counts, and the counts are computed by the pipeline's own helpers rather than by a second
/// guess at what it does — `ScanPlanTests` pins them against `ScanPipeline` so that adding a
/// stage without telling the user about it breaks a test.
public struct ScanPlan: Equatable, Sendable {

    /// One kind of thing, and what will happen to it.
    public struct Line: Equatable, Sendable, Identifiable {
        public let kind: MediaKind
        /// How many of this kind the scan knows about.
        public let indexed: Int
        /// How many of those will actually be opened and read.
        public let read: Int
        /// What they occupy, paired Live Photo movies included.
        public let bytes: Int64

        public var id: Int { kind.rawValue }

        public init(kind: MediaKind, indexed: Int, read: Int, bytes: Int64) {
            self.kind = kind
            self.indexed = indexed
            self.read = read
            self.bytes = bytes
        }
    }

    /// Present kinds only, in the order `MediaKind` declares them. A row reading "Documents 0"
    /// is noise on a screen whose job is to say what is about to happen.
    public let lines: [Line]
    public let indexed: Int
    public let read: Int
    /// Originals that live only in iCloud. Set aside before any work is scheduled against
    /// them: reading one means downloading it, and the point of the scan is to free space
    /// rather than to spend someone's data allowance filling it.
    public let cloudOnly: Int
    /// How many came from a folder the user handed over rather than from the photo library.
    public let fromFolders: Int

    /// Exactly which items the plan expects to be opened. Not public, because a screen has no
    /// use for it — it exists so the test that pins this against `ScanPipeline` can compare
    /// the two sets item by item rather than settle for comparing their sizes.
    let promisedIDs: Set<String>

    public var bytes: Int64 { lines.reduce(0) { $0 + $1.bytes } }
    public var isEmpty: Bool { indexed == 0 }
    /// How many are indexed but never opened — matched on metadata alone, or not at all.
    public var untouched: Int { max(0, indexed - read) }

    public static func of(
        _ items: [MediaItem],
        configuration: ScanConfiguration = .default
    ) -> ScanPlan {
        let local = items.filter(\.isLocallyAvailable)

        // Stage 2 of the pipeline: anything that shares kind, pixel size and byte count with
        // something else is digested, whatever kind it is.
        var willRead = Set(ScanPipeline.metadataSuspects(local).map(\.id))

        // Stage 3: every local image, without exception. This is the line the old copy hid.
        for item in local where item.kind == .image {
            willRead.insert(item.id)
        }

        // Stage 4: a video is opened only when another video is close enough in length, and in
        // shape, to be worth the decode. Both of those are metadata, so the count is knowable
        // here rather than only in hindsight.
        for pair in ScanPipeline.videoCandidatePairs(
            local,
            tolerance: configuration.videoDurationTolerance,
            shapeTolerance: configuration.videoShapeTolerance
        ) {
            willRead.insert(pair.a)
            willRead.insert(pair.b)
        }

        var lines: [Line] = []
        for kind in MediaKind.allCases {
            let ofKind = items.filter { $0.kind == kind }
            guard !ofKind.isEmpty else { continue }
            lines.append(
                Line(
                    kind: kind,
                    indexed: ofKind.count,
                    read: ofKind.reduce(0) { $0 + (willRead.contains($1.id) ? 1 : 0) },
                    bytes: ofKind.reduce(Int64(0)) { $0 + $1.totalByteSize }
                )
            )
        }

        return ScanPlan(
            lines: lines,
            indexed: items.count,
            read: willRead.count,
            cloudOnly: items.count - local.count,
            fromFolders: items.reduce(0) { $0 + ($1.source == .fileFolder ? 1 : 0) },
            promisedIDs: willRead
        )
    }
}
