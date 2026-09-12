import Foundation

/// What a file looked like when it was scanned.
///
/// A scan reads a file, decides it is a duplicate, and the user may act on that decision much
/// later — after lunch, or tomorrow. In between, the file can be replaced by something else
/// with the same name, and nothing about the identifier would change. Deleting then destroys
/// content that was never examined, which is precisely the mistake this app exists to avoid.
///
/// So the deleter is told what it expects to find, and leaves anything else alone. A photo
/// library asset needs none of this — its identifier moves with the asset, and Photos keeps
/// deletions recoverable for thirty days — but a file is gone the moment it is removed.
public struct FileStamp: Sendable, Hashable, Codable {

    public let byteSize: Int64
    public let modificationDate: Date?

    public init(byteSize: Int64, modificationDate: Date?) {
        self.byteSize = max(byteSize, 0)
        self.modificationDate = modificationDate
    }

    public init(_ item: MediaItem) {
        self.init(byteSize: item.byteSize, modificationDate: item.modificationDate)
    }

    /// Filesystem timestamps come back with sub-second noise depending on which API produced
    /// them, so a second of slack. A file rewritten in place moves by far more than that; if it
    /// somehow does not, the size check is the other half of the answer.
    public static let timestampSlack: TimeInterval = 1

    public func matches(byteSize: Int64, modificationDate: Date?) -> Bool {
        guard byteSize == self.byteSize else { return false }

        switch (self.modificationDate, modificationDate) {
        case (nil, nil):
            return true
        case let (expected?, found?):
            return abs(expected.timeIntervalSince(found)) <= Self.timestampSlack
        default:
            // One side knows a date and the other does not. That is a different answer, not the
            // same one, and this is a deletion.
            return false
        }
    }
}
