import XCTest
@testable import DupeCore

/// The vector Vision produces for an image, and the only thing this package does with it:
/// compare two of them, and put one on disk.
///
/// Nothing here imports Vision. The framework produces these; the engine compares them; keeping
/// the comparison in a package that cannot import Vision is what stops the two from drifting
/// into one untestable lump.
final class FeaturePrintTests: XCTestCase {

    private func print(_ elements: [Float], revision: String = "vision.revision2") -> FeaturePrint {
        FeaturePrint(descriptor: revision, elements: elements)
    }

    // MARK: - Distance

    func testAPrintIsNoDistanceFromItself() {
        let one = print([0.5, 0.5, 0.5, 0.5])

        XCTAssertEqual(one.distance(to: one) ?? .nan, 0, accuracy: 1e-9)
    }

    func testTheDistanceIsSquaredEuclidean() {
        // Measured and written down in docs/OPPORTUNITIES.md §9.2: squared Euclidean, equal to
        // twice the cosine distance on the L2-normalised vectors Vision returns. Hand-computed
        // here so the definition is pinned rather than remembered.
        let a = print([1, 0, 0, 0])
        let b = print([0, 1, 0, 0])

        XCTAssertEqual(a.distance(to: b) ?? .nan, 2.0, accuracy: 1e-9)
    }

    func testDistanceReadsTheSameBothWays() {
        let a = print([0.1, 0.9, 0.2, 0.35])
        let b = print([0.7, 0.1, 0.65, 0.2])

        XCTAssertEqual(a.distance(to: b) ?? .nan, b.distance(to: a) ?? .nan, accuracy: 1e-12)
    }

    func testOppositeUnitVectorsSitAtTheFarEndOfTheRange() {
        let a = print([1, 0])
        let b = print([-1, 0])

        XCTAssertEqual(a.distance(to: b) ?? .nan, 4.0, accuracy: 1e-9, "the range is [0, 4] for normalised vectors")
    }

    // MARK: - When two prints must not be compared at all

    func testTwoRevisionsAreNotComparable() {
        let two = print([1, 0], revision: "vision.revision2")
        let one = print([1, 0], revision: "vision.revision1")

        XCTAssertNil(
            two.distance(to: one),
            "Vision throws across revisions rather than returning a number, and a number here would be garbage wearing a decimal point"
        )
    }

    func testTwoLengthsAreNotComparable() {
        let long = print([1, 0, 0])
        let short = print([1, 0])

        XCTAssertNil(long.distance(to: short))
    }

    // MARK: - Going to disk and back

    func testBytesSurviveARoundTrip() {
        let original = print([0.25, -0.5, 0.125, 1])

        let decoded = FeaturePrint(decoding: original.encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded?.distance(to: original) ?? .nan, 0, accuracy: 1e-12)
    }

    func testTheRevisionSurvivesTheRoundTrip() {
        let original = print([1, 0], revision: "vision.revision2")

        XCTAssertEqual(FeaturePrint(decoding: original.encoded)?.descriptor, "vision.revision2")
    }

    func testAVectorCostsFourBytesAnElementAndNotTwelve() {
        // The reason this format exists at all. The fingerprint cache was JSON, and 768 floats
        // written as text is eight to twelve kilobytes an asset — four hundred megabytes across
        // a fifty-thousand-item library, decoded on every launch.
        let vector = print(Array(repeating: 0.5, count: 768))

        XCTAssertLessThan(
            vector.encoded.count,
            3_200,
            "768 float32 is 3072 bytes; anything much past that means the floats are being written as something other than floats"
        )
    }

    func testTruncatedBytesDecodeToNothing() {
        let original = print([0.25, -0.5, 0.125, 1])
        let cut = original.encoded.dropLast(3)

        XCTAssertNil(
            FeaturePrint(decoding: Data(cut)),
            "a half-written cache entry has to read as absent, not as a vector with a corrupt tail"
        )
    }

    func testEmptyBytesDecodeToNothing() {
        XCTAssertNil(FeaturePrint(decoding: Data()))
    }

    // MARK: - Proximity, which is distance with a budget

    func testAPairInsideTheLimitReportsExactlyWhatTheFullDistanceReports() {
        let a = print([1, 0, 0, 0])
        let b = print([0, 1, 0, 0])

        guard case let .within(measured) = a.proximity(to: b, within: 3) else {
            return XCTFail("2.0 is inside a limit of 3")
        }
        XCTAssertEqual(measured, a.distance(to: b) ?? .nan, accuracy: 1e-12)
    }

    func testAPairOnTheLimitIsInsideIt() {
        let a = print([1, 0])
        let b = print([0, 1])

        guard case .within = a.proximity(to: b, within: 2.0) else {
            return XCTFail("the limit is the last value that still counts as a match, not the first that does not")
        }
    }

    func testAPairBeyondTheLimitIsRefusedRatherThanMeasured() {
        let a = print([1, 0])
        let b = print([-1, 0])

        XCTAssertEqual(a.proximity(to: b, within: 0.2), .beyond)
    }

    /// The early exit is an optimisation, and an optimisation that changes an answer is a bug.
    /// The difference is planted at the tail here, so a version that stopped accumulating early
    /// and returned what it had would report a smaller distance than the full computation.
    func testStoppingEarlyNeverChangesTheDistanceOfAPairThatMatches() {
        var near = [Float](repeating: 0, count: 768)
        var far = [Float](repeating: 0, count: 768)
        near[0] = 1
        far[0] = 1
        far[767] = 0.3

        let a = print(near)
        let b = print(far)

        guard case let .within(measured) = a.proximity(to: b, within: 0.2) else {
            return XCTFail("0.09 is inside 0.2")
        }
        XCTAssertEqual(measured, a.distance(to: b) ?? .nan, accuracy: 1e-12)
    }

    func testTwoRevisionsAreIncomparableRatherThanFarApart() {
        let two = print([1, 0], revision: "vision.revision2")
        let one = print([1, 0], revision: "vision.revision1")

        XCTAssertEqual(
            two.proximity(to: one, within: 0.2),
            .incomparable,
            "a caller that reads this as `beyond` files two revisions as a non-match, which is a different claim from having no opinion"
        )
    }
}
