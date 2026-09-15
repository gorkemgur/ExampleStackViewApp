import Foundation

/// What Vision saw in an image, and the two things this package does with it: compare two of
/// them, and put one on disk.
///
/// Deliberately not a Vision type. `DupeCore` does not import Vision — the framework produces
/// these in the app target, the engine compares them here, and the seam is what lets the
/// comparison be tested at all. It also means the on-disk format is ours: a `VNFeaturePrint`
/// archived by Vision would tie the cache to whatever Apple does next.
///
/// ## Why this exists
///
/// Measured, and written down in `docs/OPPORTUNITIES.md` §9.1: a 30 % crop scores 34 out of 64
/// against our dHash/pHash — bit for bit the same as a completely unrelated photograph. No
/// threshold can separate those two cases, so the bottom of the ladder was never going to work.
/// The same pair scores 0.1036 and 1.6697 here.
public struct FeaturePrint: Sendable, Hashable {

    /// Which Vision revision produced the vector.
    ///
    /// Carried rather than assumed, because two revisions are not comparable: Vision itself
    /// throws across them, and revision 1 is 2048 elements against revision 2's 768. Vision
    /// hands this back as `originatingRequestDescriptor`, which makes it a staleness key the
    /// framework maintains for us — the same job `MediaItem.fingerprintFormat` does for the
    /// rest of a fingerprint.
    public let descriptor: String

    /// The vector. L2-normalised by Vision, 768 elements at revision 2.
    public let elements: [Float]

    public init(descriptor: String, elements: [Float]) {
        self.descriptor = descriptor
        self.elements = elements
    }

    // MARK: - Comparison

    /// Squared Euclidean distance, which is what Vision's own `computeDistance` returns.
    ///
    /// Measured to five decimals against a manual computation: it is exactly twice the cosine
    /// distance on these normalised vectors, so the range is [0, 4] and cosine similarity is
    /// `1 - distance / 2`.
    ///
    /// **It is not a metric.** There is no triangle inequality on a squared distance, so
    /// anything that wants to prune with a metric tree has to take `sqrt` first. A BK-tree was
    /// tried and removed as useless at our radii; this note is here so nobody reintroduces one
    /// on the assumption that these numbers behave.
    ///
    /// `nil` means *these two cannot be compared* — different revisions, or different lengths.
    /// It does not mean "far apart", and a caller that treats it as a large number will quietly
    /// stop matching anything.
    public func distance(to other: FeaturePrint) -> Double? {
        guard descriptor == other.descriptor, elements.count == other.elements.count else {
            return nil
        }

        var total = 0.0
        for index in elements.indices {
            let delta = Double(elements[index]) - Double(other.elements[index])
            total += delta * delta
        }
        return total
    }

    /// How close two prints are, when the caller only cares up to a point.
    ///
    /// Three answers, because there are three states and folding any two of them together is a
    /// bug that reads as a threshold: *these cannot be compared*, *these are further apart than
    /// you asked about*, and *these are this far apart*.
    ///
    /// Stops accumulating the moment the running total passes `limit`. Every term is a square
    /// and therefore non-negative, so a total that has already passed the limit can never come
    /// back under it — the early exit changes the cost and not the answer. It matters because
    /// this runs on every pair: two unrelated photographs sit around 1.67 apart and cross a
    /// limit of 0.2 within the first hundred or so of 768 elements.
    public func proximity(to other: FeaturePrint, within limit: Double) -> Proximity {
        guard descriptor == other.descriptor, elements.count == other.elements.count else {
            return .incomparable
        }

        var total = 0.0
        for index in elements.indices {
            let delta = Double(elements[index]) - Double(other.elements[index])
            total += delta * delta
            if total > limit { return .beyond }
        }
        return .within(total)
    }

    // MARK: - On disk

    /// `descriptor` length, the descriptor's UTF-8, then the elements as little-endian float32.
    ///
    /// Bytes rather than JSON, and the difference is not a preference. The fingerprint cache
    /// was `JSONEncoder`: 768 floats written as text is eight to twelve kilobytes an asset,
    /// which across a fifty-thousand-item library is several hundred megabytes of text parsed
    /// on every launch. As float32 the same vector is 3072 bytes and needs no parsing.
    public var encoded: Data {
        let name = Data(descriptor.utf8)
        var out = Data(capacity: 4 + name.count + elements.count * 4)

        withUnsafeBytes(of: UInt32(name.count).littleEndian) { out.append(contentsOf: $0) }
        out.append(name)
        for element in elements {
            withUnsafeBytes(of: element.bitPattern.littleEndian) { out.append(contentsOf: $0) }
        }
        return out
    }

    /// `nil` for anything that is not exactly this format, including a short read.
    ///
    /// A cache entry that was half-written has to read as absent. Decoding it into a vector
    /// with a corrupt tail would produce distances that are numbers, which is the one failure
    /// mode nothing downstream could notice.
    public init?(decoding data: Data) {
        guard data.count >= 4 else { return nil }

        let bytes = [UInt8](data)
        let nameLength = Int(
            UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        )

        let elementsStart = 4 + nameLength
        guard
            nameLength > 0,
            bytes.count >= elementsStart,
            let name = String(bytes: bytes[4..<elementsStart], encoding: .utf8)
        else { return nil }

        let remaining = bytes.count - elementsStart
        guard remaining > 0, remaining % 4 == 0 else { return nil }

        var values: [Float] = []
        values.reserveCapacity(remaining / 4)
        var index = elementsStart
        // `index + 4 <= count`, not `index < count`. The guard above already rejects a length
        // that is not a whole number of floats, so this looks redundant — and it was, until a
        // mutation removed that guard and the test process died with "Index out of range"
        // instead of failing. This reads a file that can be truncated by a crash or a full
        // disk; the loop does not get to be the thing that trusts it.
        while index + 4 <= bytes.count {
            let pattern = UInt32(bytes[index])
                | UInt32(bytes[index + 1]) << 8
                | UInt32(bytes[index + 2]) << 16
                | UInt32(bytes[index + 3]) << 24
            values.append(Float(bitPattern: pattern))
            index += 4
        }

        self.init(descriptor: name, elements: values)
    }
}

/// The three answers `FeaturePrint.proximity(to:within:)` can give.
///
/// `incomparable` is not a large distance. Two revisions of Vision produce vectors that mean
/// different things, and a caller that reads "cannot say" as "far apart" turns every
/// cache entry written by an older build into a silent non-match.
public enum Proximity: Sendable, Hashable {
    case incomparable
    case beyond
    case within(Double)
}
