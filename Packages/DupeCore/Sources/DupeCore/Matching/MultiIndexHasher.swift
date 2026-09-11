import Foundation

/// Banded index over 64-bit hashes.
///
/// A hash is cut into four 16-bit bands. If two hashes differ by at most three bits then by
/// the pigeonhole principle at least one band is byte-for-byte identical, so an exact lookup
/// per band finds every true match. That makes it an exhaustive — not heuristic — pre-filter
/// for the tight threshold, and a cheap first pass before the BK-tree handles wider searches.
public struct MultiIndexHasher {

    /// The largest distance for which `candidates(for:)` is guaranteed to miss nothing.
    public static let guaranteedDistance = 3

    private static let bandCount = 4
    private static let bandWidth = 16

    private var bands: [[UInt16: [String]]]

    public init() {
        bands = Array(repeating: [:], count: Self.bandCount)
    }

    public mutating func insert(value: UInt64, id: String) {
        for band in 0..<Self.bandCount {
            let key = Self.band(band, of: value)
            bands[band][key, default: []].append(id)
        }
    }

    /// Ids sharing at least one 16-bit band with `value`. Callers still verify the real
    /// distance; this only narrows the field.
    public func candidates(for value: UInt64, excluding excludedID: String? = nil) -> Set<String> {
        var result = Set<String>()
        for band in 0..<Self.bandCount {
            let key = Self.band(band, of: value)
            if let ids = bands[band][key] {
                result.formUnion(ids)
            }
        }
        if let excludedID { result.remove(excludedID) }
        return result
    }

    private static func band(_ index: Int, of value: UInt64) -> UInt16 {
        UInt16(truncatingIfNeeded: value >> UInt64(index * bandWidth))
    }
}
