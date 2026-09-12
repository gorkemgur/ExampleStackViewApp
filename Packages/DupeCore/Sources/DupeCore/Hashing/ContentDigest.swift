import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// A SHA-256 digest of file content.
public struct ContentDigest: Hashable, Sendable, Codable, CustomStringConvertible {

    public let bytes: [UInt8]

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    public var hexString: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public var description: String { hexString }
}

#if canImport(CryptoKit)

/// Incremental SHA-256 so a multi-gigabyte video is never held in memory at once.
public struct StreamingDigest {

    private var hasher = SHA256()

    public init() {}

    public mutating func update(_ data: Data) {
        hasher.update(data: data)
    }

    public mutating func update(_ bytes: [UInt8]) {
        hasher.update(data: Data(bytes))
    }

    /// `SHA256.finalize()` does not consume the state, so the value stays usable for tests.
    public func finalized() -> ContentDigest {
        ContentDigest(bytes: Array(hasher.finalize()))
    }
}

/// Cheap pre-filter digest: the head and tail of a file plus its exact length.
///
/// Two files with different quick digests cannot be identical, so the expensive full pass
/// only ever runs on items that already agree on size *and* on both edge windows.
public enum QuickDigest {

    /// Bytes read from each end of the file.
    public static let windowSize = 64 * 1024

    public static func compose(head: Data, tail: Data, totalBytes: Int64) -> ContentDigest {
        var hasher = SHA256()
        hasher.update(data: head)
        hasher.update(data: tail)
        withUnsafeBytes(of: totalBytes.littleEndian) { hasher.update(bufferPointer: $0) }
        return ContentDigest(bytes: Array(hasher.finalize()))
    }
}

#endif
