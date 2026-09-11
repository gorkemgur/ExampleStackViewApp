import Foundation

/// Disjoint-set forest with path compression and union by rank.
public struct UnionFind {

    private var parent: [Int]
    private var rank: [Int]

    public init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    public mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root { root = parent[root] }
        var current = element
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    @discardableResult
    public mutating func union(_ lhs: Int, _ rhs: Int) -> Bool {
        let lhsRoot = find(lhs)
        let rhsRoot = find(rhs)
        guard lhsRoot != rhsRoot else { return false }

        if rank[lhsRoot] < rank[rhsRoot] {
            parent[lhsRoot] = rhsRoot
        } else if rank[lhsRoot] > rank[rhsRoot] {
            parent[rhsRoot] = lhsRoot
        } else {
            parent[rhsRoot] = lhsRoot
            rank[lhsRoot] += 1
        }
        return true
    }

    /// Members of every set with more than one element, each group sorted ascending and the
    /// groups themselves ordered by their smallest member, so output is reproducible.
    public mutating func multiMemberGroups() -> [[Int]] {
        var buckets: [Int: [Int]] = [:]
        for element in 0..<parent.count {
            buckets[find(element), default: []].append(element)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
    }
}
