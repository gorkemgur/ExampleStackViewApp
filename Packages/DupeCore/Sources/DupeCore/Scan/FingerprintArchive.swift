import Foundation

/// The fingerprint cache, as bytes.
///
/// This used to be `JSONEncoder`, and that was a reasonable choice while a record held two
/// 64-bit numbers. A feature print is 768 float32; written as JSON text that is eight to twelve
/// kilobytes per asset, so a fifty-thousand-item library would hand `JSONDecoder` several
/// hundred megabytes of digits to parse before the first scan could start. The same vector is
/// 3072 bytes here and needs no parsing at all.
///
/// ## Reading is the dangerous half
///
/// The file is written while the app can be killed and the disk can be full, so a half-written
/// one is not hypothetical. Every read is length-checked against what is actually there, and
/// anything that does not decode *exactly* returns `nil` — one empty cache and one slow scan,
/// which is the cheapest failure in this codebase. The alternative, a record with a corrupt
/// tail, produces distances that are numbers, and nothing downstream could tell.
public enum FingerprintArchive {

    /// "DSFP", then the format version. The version is here so a later change can refuse an
    /// older file instead of reinterpreting it — the bytes of one layout are perfectly valid
    /// input to another, which is how a cache silently starts lying.
    private static let magic: [UInt8] = [0x44, 0x53, 0x46, 0x50]
    private static let version: UInt8 = 1

    private enum Field {
        static let digest: UInt8 = 1 << 0
        static let hashes: UInt8 = 1 << 1
        static let signature: UInt8 = 1 << 2
        static let featurePrint: UInt8 = 1 << 3
    }

    // MARK: - Writing

    public static func data(for records: [String: FingerprintRecord]) -> Data {
        var out = Data()
        out.append(contentsOf: magic)
        out.append(version)
        out.append(uint32: UInt32(records.count))

        // Sorted, so the same cache produces the same bytes. A file that changes when nothing
        // changed defeats every "is this different" check anyone might later put on it.
        for id in records.keys.sorted() {
            let record = records[id]!
            out.append(text: id)
            out.append(text: record.contentVersion)

            var flags: UInt8 = 0
            if record.digest != nil { flags |= Field.digest }
            if record.hashes != nil { flags |= Field.hashes }
            if record.signature != nil { flags |= Field.signature }
            if record.featurePrint != nil { flags |= Field.featurePrint }
            out.append(flags)

            if let digest = record.digest {
                out.append(uint32: UInt32(digest.bytes.count))
                out.append(contentsOf: digest.bytes)
            }
            if let hashes = record.hashes {
                out.append(uint64: hashes.dHash)
                out.append(uint64: hashes.pHash)
            }
            if let signature = record.signature {
                out.append(uint32: UInt32(signature.frameHashes.count))
                for frame in signature.frameHashes { out.append(uint64: frame) }
            }
            if let print = record.featurePrint {
                let encoded = print.encoded
                out.append(uint32: UInt32(encoded.count))
                out.append(encoded)
            }
        }

        return out
    }

    // MARK: - Reading

    /// `nil` for anything that is not exactly this format, at exactly this version, with
    /// exactly as many bytes as it claims.
    public static func records(from data: Data) -> [String: FingerprintRecord]? {
        var reader = Reader(data)

        guard
            reader.take(magic.count) == magic,
            let fileVersion = reader.byte(), fileVersion == version,
            let count = reader.uint32()
        else {
            return nil
        }

        var records: [String: FingerprintRecord] = [:]
        // Never reserved from a number the file supplied. A damaged length field says four
        // billion records and `reserveCapacity` obliges — on a phone that is a kill, and on a
        // Mac it is an overcommit that no test can see, which is the worse of the two because
        // it cannot be pinned. Reserving is an optimisation; capping it costs a rehash, and the
        // loop below runs out of bytes and returns `nil` all by itself.
        records.reserveCapacity(min(Int(count), 4096))

        for _ in 0..<count {
            guard
                let id = reader.text(),
                let contentVersion = reader.text(),
                let flags = reader.byte()
            else {
                return nil
            }

            var record = FingerprintRecord(contentVersion: contentVersion)

            if flags & Field.digest != 0 {
                guard let length = reader.uint32(), let bytes = reader.take(Int(length)) else { return nil }
                record.digest = ContentDigest(bytes: bytes)
            }
            if flags & Field.hashes != 0 {
                guard let dHash = reader.uint64(), let pHash = reader.uint64() else { return nil }
                record.hashes = PerceptualHashes(dHash: dHash, pHash: pHash)
            }
            if flags & Field.signature != 0 {
                guard let frameCount = reader.uint32(), Int(frameCount) * 8 <= reader.remaining else { return nil }
                var frames: [UInt64] = []
                frames.reserveCapacity(Int(frameCount))
                for _ in 0..<frameCount {
                    guard let frame = reader.uint64() else { return nil }
                    frames.append(frame)
                }
                record.signature = VideoSignature(frameHashes: frames)
            }
            if flags & Field.featurePrint != 0 {
                guard
                    let length = reader.uint32(),
                    let bytes = reader.take(Int(length)),
                    let print = FeaturePrint(decoding: Data(bytes))
                else {
                    return nil
                }
                record.featurePrint = print
            }

            records[id] = record
        }

        // Trailing bytes mean this is not the file it claims to be. Two archives concatenated
        // by a failed atomic write would otherwise decode as the first one and look healthy.
        guard reader.remaining == 0 else { return nil }
        return records
    }

    /// A cursor that cannot read past the end. Every `guard let` above depends on that being
    /// true in one place rather than at thirty call sites.
    private struct Reader {

        private let bytes: [UInt8]
        private var index = 0

        init(_ data: Data) { bytes = [UInt8](data) }

        var remaining: Int { bytes.count - index }

        mutating func take(_ count: Int) -> [UInt8]? {
            guard count >= 0, remaining >= count else { return nil }
            defer { index += count }
            return Array(bytes[index..<(index + count)])
        }

        mutating func byte() -> UInt8? {
            guard remaining >= 1 else { return nil }
            defer { index += 1 }
            return bytes[index]
        }

        mutating func uint32() -> UInt32? {
            guard let raw = take(4) else { return nil }
            return UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16 | UInt32(raw[3]) << 24
        }

        mutating func uint64() -> UInt64? {
            guard let raw = take(8) else { return nil }
            var value: UInt64 = 0
            for offset in (0..<8).reversed() { value = value << 8 | UInt64(raw[offset]) }
            return value
        }

        mutating func text() -> String? {
            guard let length = uint32(), let raw = take(Int(length)) else { return nil }
            return String(bytes: raw, encoding: .utf8)
        }
    }
}

private extension Data {

    mutating func append(uint32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(uint64 value: UInt64) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(text value: String) {
        let utf8 = Data(value.utf8)
        append(uint32: UInt32(utf8.count))
        append(utf8)
    }
}
