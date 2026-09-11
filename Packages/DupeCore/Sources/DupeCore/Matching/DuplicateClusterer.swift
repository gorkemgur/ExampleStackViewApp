import Foundation

/// Turns pairwise evidence into groups.
///
/// Two different strategies, because the two kinds of evidence have different mathematical
/// standing:
///
/// * **Exact** matches come from digest equality, which is transitive. Union-find is correct.
/// * **Similar** matches come from a distance threshold, which is *not* transitive: A~B and
///   B~C says nothing about A~C. Clustering these with union-find is how a duplicate finder
///   ends up deleting a photo nobody ever compared against the survivor. So similar items are
///   clustered as stars around the highest-ranked member, and that member is the one kept.
public enum DuplicateClusterer {

    /// Groups items that share an identical content key.
    public static func exactGroups<Key: Hashable>(keys: [String: Key]) -> [DuplicateGroup] {
        var buckets: [Key: [String]] = [:]
        for (id, key) in keys {
            buckets[key, default: []].append(id)
        }

        return buckets
            .values
            .filter { $0.count > 1 }
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
            .map { members in
                DuplicateGroup(
                    id: "exact:\(members[0])",
                    relation: .exact,
                    seedID: members[0],
                    itemIDs: members
                )
            }
    }

    /// Groups items linked by perceptual distance.
    ///
    /// - Parameters:
    ///   - edges: verified pairs. Anything above `maxDistance` is ignored.
    ///   - rank: how good a survivor each item would make; the best-ranked available item
    ///     becomes the seed, and every other member of its group is a direct neighbour of it.
    ///   - relation: the confidence label to stamp on the produced groups.
    /// - Returns: groups of two or more, each item appearing in at most one group.
    public static func similarGroups(
        edges: [SimilarityEdge],
        rank: [String: Double],
        maxDistance: Int,
        relation: DuplicateRelation = .similar
    ) -> [DuplicateGroup] {

        var adjacency: [String: [(id: String, distance: Int)]] = [:]
        for edge in edges where edge.distance <= maxDistance && edge.a != edge.b {
            adjacency[edge.a, default: []].append((id: edge.b, distance: edge.distance))
            adjacency[edge.b, default: []].append((id: edge.a, distance: edge.distance))
        }
        guard !adjacency.isEmpty else { return [] }

        // Highest rank first; ties broken by id so runs are reproducible.
        let seedOrder = adjacency.keys.sorted { lhs, rhs in
            let lhsRank = rank[lhs] ?? 0
            let rhsRank = rank[rhs] ?? 0
            return lhsRank == rhsRank ? lhs < rhs : lhsRank > rhsRank
        }

        var consumed = Set<String>()
        var groups: [DuplicateGroup] = []

        for seed in seedOrder {
            guard !consumed.contains(seed) else { continue }

            // Deduplicate neighbours, keeping the closest observed distance for each.
            var closest: [String: Int] = [:]
            for neighbour in adjacency[seed] ?? [] where !consumed.contains(neighbour.id) && neighbour.id != seed {
                if let existing = closest[neighbour.id] {
                    closest[neighbour.id] = min(existing, neighbour.distance)
                } else {
                    closest[neighbour.id] = neighbour.distance
                }
            }
            guard !closest.isEmpty else { continue }

            let members = closest
                .sorted { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
                }
                .map(\.key)

            consumed.insert(seed)
            consumed.formUnion(members)

            groups.append(
                DuplicateGroup(
                    id: "\(relation.rawValue):\(seed)",
                    relation: relation,
                    seedID: seed,
                    itemIDs: [seed] + members
                )
            )
        }

        return groups.sorted { $0.seedID < $1.seedID }
    }
}
