import Foundation

/// The receipt that travels with an export.
///
/// `docs/CONCEPT.md` promises that the original bytes of anything about to be deleted can be
/// written to a folder of the user's choosing, with a manifest beside them saying what each
/// file was and what it was being deleted in favour of. Without that second half the export is
/// a folder of opaque filenames: it is the manifest that makes a wrong decision recoverable,
/// because it is the only thing that records *which copy stayed*.
///
/// Plain JSON, pretty-printed, with sorted keys and ISO-8601 dates — a document a person can
/// open in any text editor in five years, on a machine that has never heard of this app. The
/// enums are written as words for the same reason: `"kind": 1` is not a receipt.
public struct ExportManifest: Codable, Sendable, Equatable {

    /// One exported original.
    public struct Entry: Codable, Sendable, Equatable {

        /// The app's own id for the item. Meaningless outside the app, kept because it is the
        /// only thing that ties this row to the history record of the deletion.
        public let itemID: String
        /// What the item was called in the library.
        public let displayName: String
        /// What the file is called inside the export folder. Not the same thing: two copies in
        /// one group usually share a display name, which is how they became duplicates.
        public let exportedFileName: String
        public let byteSize: Int64
        /// "image", "video" or "file".
        public let kind: String
        /// "photo library" or "folder".
        public let source: String
        public let groupID: String
        /// What deleting this was judged to cost, in the app's own words.
        public let cost: String
        /// The copy that stayed. The single most important column here: it is what turns
        /// "I deleted the wrong one" into "here is the one I meant to keep".
        public let keptItemID: String
        public let keptDisplayName: String
        public let creationDate: Date?
        /// Extra files written beside this one — the paired movie of a Live Photo, today.
        ///
        /// A file in the export folder that the manifest does not mention is the inverse of the
        /// guarantee this document exists to make, and it was happening: the paired movie was
        /// written and then described nowhere.
        public let companionFileNames: [String]

        public init(
            itemID: String,
            displayName: String,
            exportedFileName: String,
            byteSize: Int64,
            kind: String,
            source: String,
            groupID: String,
            cost: String,
            keptItemID: String,
            keptDisplayName: String,
            creationDate: Date?,
            companionFileNames: [String] = []
        ) {
            self.itemID = itemID
            self.displayName = displayName
            self.exportedFileName = exportedFileName
            self.byteSize = byteSize
            self.kind = kind
            self.source = source
            self.groupID = groupID
            self.cost = cost
            self.keptItemID = keptItemID
            self.keptDisplayName = keptDisplayName
            self.creationDate = creationDate
            self.companionFileNames = companionFileNames
        }

        /// The same row, naming what else landed beside it.
        public func withCompanions(_ names: [String]) -> Entry {
            Entry(
                itemID: itemID,
                displayName: displayName,
                exportedFileName: exportedFileName,
                byteSize: byteSize,
                kind: kind,
                source: source,
                groupID: groupID,
                cost: cost,
                keptItemID: keptItemID,
                keptDisplayName: keptDisplayName,
                creationDate: creationDate,
                companionFileNames: names
            )
        }
    }

    /// Bumped if the shape ever changes, so a reader five years from now knows what it is
    /// looking at rather than guessing from the keys.
    public let formatVersion: Int
    public let createdAt: Date
    public let note: String
    public let entries: [Entry]

    public init(createdAt: Date, entries: [Entry]) {
        self.formatVersion = 1
        self.createdAt = createdAt
        self.note = "Original bytes of the copies DupeSpace was asked to delete. Each entry names the copy that was kept in its place."
        self.entries = entries
    }

    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.byteSize } }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> ExportManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportManifest.self, from: data)
    }
}

/// Turns a selection into manifest rows, and hands out the filename each original will take.
///
/// Pure, and in the core package rather than beside the file writer, because the naming is the
/// part that can quietly destroy an export: two copies in a group almost always share a display
/// name — that is usually *why* they matched — so writing them out under it means the second
/// one lands on top of the first and the export silently contains half of what it claims.
public enum ExportManifestBuilder {

    /// Names collide, so every file carries its group and its position in it.
    ///
    /// `IMG_4021.MOV` and `IMG_4021 (1).MOV` are the easy case. The one that bites is a burst,
    /// where thirty frames share one name exactly.
    public static func fileName(for item: MediaItem, index: Int) -> String {
        let name = item.displayName.isEmpty ? "item" : item.displayName
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let safeBase = sanitised(base.isEmpty ? "item" : base)
        let stem = "\(String(format: "%03d", index))-\(safeBase)"
        return ext.isEmpty ? stem : "\(stem).\(sanitised(ext))"
    }

    /// Everything a filesystem might choke on, and the leading dot that would hide the file.
    private static func sanitised(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ."))
        let cleaned = String(text.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return trimmed.isEmpty ? "item" : String(trimmed.prefix(60))
    }

    public static func entries(
        for candidates: [DeletionCandidate],
        items: [String: MediaItem]
    ) -> [(item: MediaItem, entry: ExportManifest.Entry)] {
        candidates.enumerated().compactMap { index, candidate in
            guard let item = items[candidate.id] else { return nil }
            let kept = items[candidate.keeperID]
            let name = fileName(for: item, index: index + 1)
            return (
                item,
                ExportManifest.Entry(
                    itemID: item.id,
                    displayName: item.displayName,
                    exportedFileName: name,
                    byteSize: item.totalByteSize,
                    kind: word(for: item.kind),
                    source: word(for: item.source),
                    groupID: candidate.groupID,
                    cost: word(for: candidate.tier),
                    keptItemID: candidate.keeperID,
                    keptDisplayName: kept?.displayName ?? candidate.keeperID,
                    creationDate: item.creationDate
                )
            )
        }
    }

    /// The tier in words. `ScanCopy` says the same thing on screen, but it lives in the app
    /// target and a manifest written into someone's folder has to be readable without it.
    private static func word(for tier: RegretTier) -> String {
        switch tier {
        case .identical: return "identical copy"
        case .inferiorCopy: return "lower-quality re-send"
        case .burstLeftover: return "burst leftover"
        case .similar: return "similar shot"
        }
    }

    private static func word(for kind: MediaKind) -> String {
        switch kind {
        case .image: return "image"
        case .video: return "video"
        case .document: return "file"
        }
    }

    private static func word(for source: MediaSource) -> String {
        switch source {
        case .photoLibrary: return "photo library"
        case .fileFolder: return "folder"
        }
    }
}
