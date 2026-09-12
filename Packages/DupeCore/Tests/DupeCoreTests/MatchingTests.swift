import XCTest
@testable import DupeCore

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
    /// Ten samples of the same frame is one observation, not ten, and the worst-frame veto —
    /// the entire reason a signature is ten numbers — has nothing left to catch. The sampler
    /// refuses to produce one of these; this is the predicate it refuses on.
    func testASignatureThatCollapsedOntoAFewFramesCarriesNoEvidence() {
        let collapsed = VideoSignature(frameHashes: Array(repeating: 0xABCD, count: 10))
        XCTAssertFalse(collapsed.carriesEnoughEvidence)
        XCTAssertEqual(collapsed.distinctFrameCount, 1)

        let real = VideoSignature(frameHashes: (0..<10).map { UInt64(1) << $0 })
        XCTAssertTrue(real.carriesEnoughEvidence)
    }

    /// Normalised sample positions mean position i already describes the same moment, so the
    /// default search is no shift at all. Callers that sample at absolute offsets can still
    /// ask for drift.
    func testTheDefaultComparisonDoesNotShift() {
        let base: [UInt64] = [1, 2, 4, 8, 16, 32, 64, 128]
        let shifted = VideoSignature(frameHashes: [0] + base.dropLast())
        let comparison = VideoMatcher.compare(VideoSignature(frameHashes: base), shifted)
        XCTAssertEqual(comparison?.shift, 0)
    }

}
