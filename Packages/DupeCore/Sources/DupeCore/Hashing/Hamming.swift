import Foundation

/// Bit distance between two 64-bit perceptual hashes.
@inlinable
public func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
    (lhs ^ rhs).nonzeroBitCount
}
