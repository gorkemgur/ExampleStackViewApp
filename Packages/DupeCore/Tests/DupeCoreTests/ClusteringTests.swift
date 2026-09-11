import XCTest
@testable import DupeCore

final class DuplicateClustererTests: XCTestCase {

    // MARK: - Exact

    func testExactGroupsByIdenticalKey() {
        let groups = DuplicateClusterer.exactGroups(keys: [
            "a": "hash-1", "b": "hash-1", "c": "hash-2", "d": "hash-1", "e": "hash-2"
        ])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].itemIDs, ["a", "b", "d"])
        XCTAssertEqual(groups[1].itemIDs, ["c", "e"])
        XCTAssertTrue(groups.allSatisfy { $0.relation == .exact })
    }

    func testExactIgnoresUniqueItems() {
        XCTAssertTrue(DuplicateClusterer.exactGroups(keys: ["a": 1, "b": 2, "c": 3]).isEmpty)
    }

    func testExactOutputIsOrderIndependent() {
        let first = DuplicateClusterer.exactGroups(keys: ["z": 1, "y": 1, "x": 2, "w": 2])
        let second = DuplicateClusterer.exactGroups(keys: ["w": 2, "x": 2, "y": 1, "z": 1])
        XCTAssertEqual(first, second)
    }

    // MARK: - Similar

    func testSimilarGroupsFormAroundTheHighestRankedItem() {
        let edges = [
            SimilarityEdge(a: "low", b: "best", distance: 4),
            SimilarityEdge(a: "mid", b: "best", distance: 6)
        ]
        let groups = DuplicateClusterer.similarGroups(
            edges: edges,
            rank: ["best": 900, "mid": 500, "low": 100],
            maxDistance: 10
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].seedID, "best")
        XCTAssertEqual(groups[0].itemIDs, ["best", "low", "mid"], "seed first, then closest")
    }

    func testEdgesBeyondThresholdAreIgnored() {
        let edges = [SimilarityEdge(a: "a", b: "b", distance: 30)]
        XCTAssertTrue(
            DuplicateClusterer.similarGroups(edges: edges, rank: [:], maxDistance: 10).isEmpty
        )
    }

    /// The property the whole design rests on: a photo is only ever proposed for deletion
    /// next to a survivor it was measured against *directly*. A - B - C where A and C are far
    /// apart must not put A and C in one group under a survivor neither of them matches.
    func testNoTransitiveChaining() {
        let edges = [
            SimilarityEdge(a: "a", b: "b", distance: 9),
            SimilarityEdge(a: "b", b: "c", distance: 9)
            // a <-> c would be ~18: never measured, never assumed
        ]
        let groups = DuplicateClusterer.similarGroups(
            edges: edges,
            rank: ["a": 10, "b": 5, "c": 1],
            maxDistance: 10
        )

        for group in groups {
            for member in group.itemIDs where member != group.seedID {
                let edge = edges.first {
                    ($0.a == group.seedID && $0.b == member) || ($0.b == group.seedID && $0.a == member)
                }
                XCTAssertNotNil(edge, "\(member) grouped with \(group.seedID) without a direct edge")
                XCTAssertLessThanOrEqual(edge!.distance, 10)
            }
        }
    }

    func testEveryItemBelongsToAtMostOneGroup() {
        var rng = SplitMix64(seed: 31337)
        var edges: [SimilarityEdge] = []
        for _ in 0..<400 {
            let a = Int.random(in: 0..<60, using: &rng)
            let b = Int.random(in: 0..<60, using: &rng)
            guard a != b else { continue }
            edges.append(SimilarityEdge(a: "i\(a)", b: "i\(b)", distance: Int.random(in: 0...12, using: &rng)))
        }
        var rank: [String: Double] = [:]
        for index in 0..<60 { rank["i\(index)"] = Double.random(in: 0...1000, using: &rng) }

        let groups = DuplicateClusterer.similarGroups(edges: edges, rank: rank, maxDistance: 10)

        var seen = Set<String>()
        for group in groups {
            XCTAssertGreaterThan(group.itemIDs.count, 1)
            XCTAssertEqual(group.itemIDs.first, group.seedID)
            for member in group.itemIDs {
                XCTAssertTrue(seen.insert(member).inserted, "\(member) appeared in two groups")
            }
        }
    }

    func testSelfEdgesAreDiscarded() {
        let edges = [SimilarityEdge(a: "a", b: "a", distance: 0)]
        XCTAssertTrue(DuplicateClusterer.similarGroups(edges: edges, rank: [:], maxDistance: 10).isEmpty)
    }

    func testSimilarityEdgeNormalisesEndpoints() {
        XCTAssertEqual(
            SimilarityEdge(a: "z", b: "a", distance: 3),
            SimilarityEdge(a: "a", b: "z", distance: 3)
        )
        XCTAssertEqual(SimilarityEdge(a: "z", b: "a", distance: 3).other(than: "a"), "z")
        XCTAssertNil(SimilarityEdge(a: "z", b: "a", distance: 3).other(than: "q"))
    }
}
