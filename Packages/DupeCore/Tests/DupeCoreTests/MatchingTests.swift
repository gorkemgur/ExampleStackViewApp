import XCTest
@testable import DupeCore

final class BKTreeTests: XCTestCase {

    func testEmptyTreeReturnsNothing() {
        let tree = BKTree()
        XCTAssertTrue(tree.isEmpty)
        XCTAssertTrue(tree.query(value: 42, maxDistance: 10).isEmpty)
    }

    func testDuplicateValuesAreAllReturned() {
        var tree = BKTree()
        tree.insert(value: 0xFF00, id: "a")
        tree.insert(value: 0xFF00, id: "b")
        let hits = tree.query(value: 0xFF00, maxDistance: 0)
        XCTAssertEqual(hits.map(\.id).sorted(), ["a", "b"])
        XCTAssertEqual(hits.map(\.distance), [0, 0])
    }

    /// The tree prunes branches using the triangle inequality; if that pruning is wrong it
    /// silently returns fewer results, which would silently hide duplicates. Cross-check
    /// every query against a brute-force scan.
    func testQueryMatchesBruteForceScan() {
        var rng = SplitMix64(seed: 99)
        var values: [(String, UInt64)] = []
        var tree = BKTree()

        for index in 0..<400 {
            let value = UInt64.random(in: .min ... .max, using: &rng)
            let id = "item-\(index)"
            values.append((id, value))
            tree.insert(value: value, id: id)
        }

        for maxDistance in [0, 3, 8, 16, 30] {
            for _ in 0..<20 {
                let probe = UInt64.random(in: .min ... .max, using: &rng)
                let expected = Set(values.filter { hammingDistance($0.1, probe) <= maxDistance }.map(\.0))
                let actual = Set(tree.query(value: probe, maxDistance: maxDistance).map(\.id))
                XCTAssertEqual(actual, expected, "mismatch at maxDistance \(maxDistance)")
            }
        }
    }

    func testResultsAreSortedByDistanceThenID() {
        var tree = BKTree()
        tree.insert(value: 0b0000, id: "zero")
        tree.insert(value: 0b0001, id: "one")
        tree.insert(value: 0b0011, id: "three")
        let hits = tree.query(value: 0, maxDistance: 4)
        XCTAssertEqual(hits.map(\.id), ["zero", "one", "three"])
    }
}

final class MultiIndexHasherTests: XCTestCase {

    /// The pigeonhole guarantee is the entire reason this index exists: within three bits it
    /// must never miss a match. If it does, duplicates go unreported.
    func testNeverMissesAMatchWithinTheGuaranteedDistance() {
        var rng = SplitMix64(seed: 4242)
        var index = MultiIndexHasher()
        var values: [(String, UInt64)] = []

        for i in 0..<300 {
            let value = UInt64.random(in: .min ... .max, using: &rng)
            values.append(("v\(i)", value))
            index.insert(value: value, id: "v\(i)")
        }

        for (id, value) in values {
            for flipCount in 0...MultiIndexHasher.guaranteedDistance {
                var probe = value
                var flipped = Set<Int>()
                while flipped.count < flipCount {
                    let bit = Int.random(in: 0..<64, using: &rng)
                    if flipped.insert(bit).inserted {
                        probe ^= (UInt64(1) << UInt64(bit))
                    }
                }
                XCTAssertTrue(
                    index.candidates(for: probe).contains(id),
                    "missed \(id) at distance \(flipCount)"
                )
            }
        }
    }

    func testExcludesTheProbeItself() {
        var index = MultiIndexHasher()
        index.insert(value: 12345, id: "self")
        index.insert(value: 12345, id: "other")
        XCTAssertEqual(index.candidates(for: 12345, excluding: "self"), ["other"])
    }
}

final class UnionFindTests: XCTestCase {

    func testUnionAndFind() {
        var uf = UnionFind(count: 6)
        XCTAssertTrue(uf.union(0, 1))
        XCTAssertTrue(uf.union(1, 2))
        XCTAssertFalse(uf.union(0, 2), "already connected")
        XCTAssertEqual(uf.find(0), uf.find(2))
        XCTAssertNotEqual(uf.find(0), uf.find(3))
    }

    func testMultiMemberGroupsAreDeterministic() {
        var uf = UnionFind(count: 7)
        uf.union(5, 1)
        uf.union(3, 6)
        uf.union(6, 0)
        XCTAssertEqual(uf.multiMemberGroups(), [[0, 3, 6], [1, 5]])
    }

    func testSingletonsAreExcluded() {
        var uf = UnionFind(count: 4)
        uf.union(0, 1)
        XCTAssertEqual(uf.multiMemberGroups(), [[0, 1]])
    }
}

final class VideoMatcherTests: XCTestCase {

    func testIdenticalSignaturesMatchExactly() {
        let signature = VideoSignature(frameHashes: [1, 2, 4, 8, 16, 32])
        let comparison = VideoMatcher.compare(signature, signature)
        XCTAssertEqual(comparison?.averageDistance, 0)
        XCTAssertEqual(comparison?.worstDistance, 0)
        XCTAssertTrue(VideoMatcher.isDuplicate(comparison!))
    }

    func testShiftedSignatureStillMatches() {
        // The same footage where the frame grabber landed one keyframe later.
        let base: [UInt64] = [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6]
        let lhs = VideoSignature(frameHashes: base)
        let rhs = VideoSignature(frameHashes: [0x00] + base.dropLast())

        let comparison = VideoMatcher.compare(lhs, rhs, maxShift: 1)
        XCTAssertEqual(comparison?.shift, 1)
        XCTAssertEqual(comparison?.averageDistance, 0)
    }

    func testTooLittleOverlapIsReportedAsNoEvidence() {
        let lhs = VideoSignature(frameHashes: [1, 2])
        let rhs = VideoSignature(frameHashes: [1, 2])
        XCTAssertNil(VideoMatcher.compare(lhs, rhs, minimumOverlap: 3))
    }

    func testOneCompletelyDifferentSceneRejectsTheMatch() {
        let lhs = VideoSignature(frameHashes: [0, 0, 0, 0, 0, 0])
        let rhs = VideoSignature(frameHashes: [0, 0, 0, UInt64.max, 0, 0])
        let comparison = VideoMatcher.compare(lhs, rhs, maxShift: 0)!
        XCTAssertEqual(comparison.worstDistance, 64)
        XCTAssertFalse(VideoMatcher.isDuplicate(comparison), "a 64-bit outlier frame must veto")
    }
}
