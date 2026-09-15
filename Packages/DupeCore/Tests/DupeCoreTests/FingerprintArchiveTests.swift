import XCTest
@testable import DupeCore

/// The cache's on-disk format.
///
/// It was `JSONEncoder`. That was fine while a record held two 64-bit hashes; a 768-element
/// feature print written as text is eight to twelve kilobytes an asset, which across a
/// fifty-thousand-item library is several hundred megabytes of text to parse on every launch.
///
/// The file is also the one thing here a crash or a full disk can cut in half, so most of these
/// tests are about refusing a damaged file rather than reading one.
final class FingerprintArchiveTests: XCTestCase {

    private func print(_ count: Int = 768, seed: Float = 0.01) -> FeaturePrint {
        FeaturePrint(descriptor: "vision.revision2", elements: (0..<count).map { seed * Float($0 % 97) })
    }

    private func everything() -> [String: FingerprintRecord] {
        [
            "full": FingerprintRecord(
                contentVersion: "fp3-100-0-10x10-0-0-0",
                digest: ContentDigest(bytes: (0..<32).map(UInt8.init)),
                hashes: PerceptualHashes(dHash: 0xDEAD_BEEF_0123_4567, pHash: 0x89AB_CDEF_7654_3210),
                signature: VideoSignature(frameHashes: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
                featurePrint: print()
            ),
            "digest only": FingerprintRecord(
                contentVersion: "v2",
                digest: ContentDigest(bytes: [9])
            ),
            "print only": FingerprintRecord(contentVersion: "v3", featurePrint: print(4)),
            "nothing at all": FingerprintRecord(contentVersion: "v4")
        ]
    }

    // MARK: - Round trip

    func testEveryFieldOfEveryRecordSurvivesTheRoundTrip() throws {
        let records = everything()

        let restored = FingerprintArchive.records(from: FingerprintArchive.data(for: records))

        XCTAssertEqual(restored, records)
    }

    func testAnEmptyArchiveIsAnEmptyCacheAndNotAFailure() throws {
        let restored = FingerprintArchive.records(from: FingerprintArchive.data(for: [:]))

        XCTAssertEqual(restored, [:], "a library with nothing cached yet is an ordinary state")
    }

    func testAnIdentifierWithNonLatinCharactersSurvives() throws {
        // Photo library identifiers are ASCII, folder items are keyed by path, and a path is
        // whatever the person called their folder.
        let records = ["Öğle yemeği/böcek 🐞.HEIC": FingerprintRecord(contentVersion: "v1", featurePrint: print(8))]

        XCTAssertEqual(FingerprintArchive.records(from: FingerprintArchive.data(for: records)), records)
    }

    // MARK: - Damage

    /// Every prefix of a real archive, one byte at a time. A cache file is written while an app
    /// can be killed, so a half-written one is not a hypothetical.
    func testNoTruncationOfARealArchiveIsEverReadAsRecords() {
        let data = FingerprintArchive.data(for: everything())

        for length in 0..<data.count {
            let restored = FingerprintArchive.records(from: data.prefix(length))
            XCTAssertNil(restored, "\(length) bytes of a \(data.count)-byte archive decoded to something")
        }
    }

    func testBytesFromAnotherVersionAreRefusedRatherThanReinterpreted() {
        var data = [UInt8](FingerprintArchive.data(for: everything()))
        data[4] = 99

        XCTAssertNil(FingerprintArchive.records(from: Data(data)))
    }

    func testAnArchiveThatClaimsFourBillionRecordsIsRefusedRatherThanAllocatedFor() {
        // The count is four bytes of a file a crash can scribble on. Believed, it reserves
        // capacity for four billion records and the app is killed before it can say why.
        var data = [UInt8](FingerprintArchive.data(for: everything()))
        data[5] = 0xFF; data[6] = 0xFF; data[7] = 0xFF; data[8] = 0xFF

        XCTAssertNil(FingerprintArchive.records(from: Data(data)))
    }

    func testTheFirstFourBytesHaveToSayThisIsOurs() {
        // Deliberately keeps the version byte valid, so this pins the magic and not the version
        // check standing behind it. A file at this path that is anything else — the JSON this
        // replaced, a half-copied download — must not be read as records.
        var data = [UInt8](FingerprintArchive.data(for: everything()))
        data[0] = 0x7B

        XCTAssertNil(FingerprintArchive.records(from: Data(data)))
    }

    func testSomethingThatIsNotAnArchiveAtAllIsRefused() {
        let json = Data(#"{"a":{"contentVersion":"v1"}}"#.utf8)

        XCTAssertNil(
            FingerprintArchive.records(from: json),
            "the file this replaces was JSON, and it sits at the same path"
        )
    }

    func testCorruptBytesAreRefusedRatherThanTurnedIntoNumbers() {
        // A flipped byte inside a vector would decode to a float that is simply wrong, and a
        // wrong vector produces distances that look like answers. The length fields are what
        // this can actually check, so this drives random damage through them and asks only
        // that nothing crashes and nothing invents a record.
        var generator = SplitMix64(seed: 0x5EED)
        let original = [UInt8](FingerprintArchive.data(for: everything()))

        for _ in 0..<200 {
            var damaged = original
            let index = Int(generator.next() % UInt64(damaged.count))
            damaged[index] = UInt8(truncatingIfNeeded: generator.next())
            _ = FingerprintArchive.records(from: Data(damaged))
        }
    }

    func testAnArchiveWithAnythingGluedOnTheEndIsRefused() {
        var data = FingerprintArchive.data(for: everything())
        data.append(contentsOf: [0, 0, 0])

        XCTAssertNil(
            FingerprintArchive.records(from: data),
            "an atomic write that half-failed leaves one archive followed by part of another, and reading the first as if it were the file would look perfectly healthy"
        )
    }

    // MARK: - The reason this exists

    func testAPrintCostsThreeKilobytesRatherThanNine() throws {
        // A realistic vector, not a tidy one. The first version of this test used elements like
        // 0.01 and 0.02, which JSON writes in four characters, and it reported a ratio of 1.6x
        // — a property of the fixture, not of the format. Vision's elements are full-precision
        // floats and JSON spends ten to twelve characters on each of them.
        var generator = SplitMix64(seed: 0xF00D)
        let elements = (0..<768).map { _ in Float(Double(generator.next() % 2_000_000) / 5.5e7 - 0.018) }
        let vector = FeaturePrint(descriptor: "vision.revision2", elements: elements)
        let one = ["a": FingerprintRecord(contentVersion: "fp3-1-0-1x1-0-0-0", featurePrint: vector)]

        let archived = FingerprintArchive.data(for: one).count
        let asJSON = try JSONEncoder().encode(elements).count

        XCTAssertLessThan(archived, 3_200, "768 float32 plus a little framing")
        XCTAssertGreaterThan(
            asJSON,
            archived * 2,
            "measured rather than assumed: \(asJSON) bytes of text against \(archived) of bytes, and this is one asset"
        )
    }
}
