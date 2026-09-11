import Foundation

/// Metric tree over 64-bit hashes under Hamming distance.
///
/// Lets the near-duplicate pass ask "everything within d bits of this hash" without the
/// O(n^2) sweep a 50 000-item library would otherwise need.
public struct BKTree {

    private struct Node {
        let value: UInt64
        var ids: [String]
        /// distance -> index into `nodes`
        var children: [Int: Int]
    }

    private var nodes: [Node] = []

    public init() {}

    public var isEmpty: Bool { nodes.isEmpty }

    public mutating func insert(value: UInt64, id: String) {
        guard !nodes.isEmpty else {
            nodes.append(Node(value: value, ids: [id], children: [:]))
            return
        }

        var currentIndex = 0
        while true {
            let distance = hammingDistance(value, nodes[currentIndex].value)
            if distance == 0 {
                nodes[currentIndex].ids.append(id)
                return
            }
            if let childIndex = nodes[currentIndex].children[distance] {
                currentIndex = childIndex
                continue
            }
            nodes.append(Node(value: value, ids: [id], children: [:]))
            nodes[currentIndex].children[distance] = nodes.count - 1
            return
        }
    }

    /// Every stored id whose hash is within `maxDistance` bits of `value`.
    public func query(value: UInt64, maxDistance: Int) -> [(id: String, distance: Int)] {
        guard !nodes.isEmpty, maxDistance >= 0 else { return [] }

        var results: [(id: String, distance: Int)] = []
        var stack = [0]

        while let index = stack.popLast() {
            let node = nodes[index]
            let distance = hammingDistance(value, node.value)
            if distance <= maxDistance {
                for id in node.ids {
                    results.append((id: id, distance: distance))
                }
            }
            // The triangle inequality bounds which children can still be in range.
            let lower = distance - maxDistance
            let upper = distance + maxDistance
            for (childDistance, childIndex) in node.children where childDistance >= lower && childDistance <= upper {
                stack.append(childIndex)
            }
        }

        return results.sorted { lhs, rhs in
            lhs.distance == rhs.distance ? lhs.id < rhs.id : lhs.distance < rhs.distance
        }
    }
}
