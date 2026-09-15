import XCTest
@testable import DupeCore

/// What the engine does on a library nobody has ever run it against.
///
/// Every measurement this project has is from a twenty-eight item fixture. The matching stage
/// is an n-squared sweep by design (`ScanPipeline.edges` — the BK-tree was measured useless at
/// these radii and removed), bounded in memory by `maximumNeighboursPerItem` and not bounded in
/// time at all. Nobody had asked what that costs at five hundred, a thousand, or two thousand
/// items, or whether the answers are still right up there.
///
/// These tests are in `DupeCore` on purpose: no simulator, no app target, no Vision. `swift
/// test` runs them, so the cheapest signal about scale is also the first one available.
final class ScanScaleTests: XCTestCase {

    // MARK: - A library big enough to be worth measuring

    /// A synthetic camera roll: mostly photographs of different things, with a fifth of it in
    /// near-duplicate pairs.
    ///
    /// The proportions matter more than the size. A corpus of nothing but duplicates would
    /// measure the clustering and never the sweep, and it is the sweep — every item against
    /// every other one — that the whole library pays for.
    struct Corpus {

        let items: [MediaItem]
        let analyzer: any AssetAnalyzing
        /// Pairs planted as `pair-<i>-a` / `pair-<i>-b`, each within the similar threshold.
        let pairCount: Int

        /// - Parameters:
        ///   - count: how many items in total.
        ///   - withPrints: whether the analyzer answers with feature prints as well as hashes.
        ///     Off is the world before slice 2 and the control this measurement needs: the
        ///     print path costs 768 floats a pair where the hash path costs an XOR.
        ///   - pile: a run of mutually near-identical items on top of `count`, the shape
        ///     `maximumNeighboursPerItem` exists for. Ids are `pile-<i>`.
        init(count: Int, withPrints: Bool = true, pile: Int = 0) {
            let pairCount = count / 10
            self.pairCount = pairCount

            var items: [MediaItem] = []
            var hashes: [String: PerceptualHashes] = [:]
            var prints: [String: FeaturePrint] = [:]

            // A fifth of the library is in pairs: 0.03 apart, which is past the near-exact
            // limit of 0.02 and well inside the similar limit of 0.20 — a re-send, not a
            // second copy.
            for index in 0..<pairCount {
                let base = Self.unitVector(seed: UInt64(index) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
                let (first, second) = Self.tilted(base, apart: 0.03, seed: UInt64(index) &+ 0xBEEF)

                let seed = Self.scramble(UInt64(index) &+ 0x5EED_0000)
                hashes["pair-\(index)-a"] = PerceptualHashes(dHash: seed, pHash: Self.scramble(seed))
                hashes["pair-\(index)-b"] = PerceptualHashes(
                    dHash: Self.flipping(seed, bits: 7),
                    pHash: Self.flipping(Self.scramble(seed), bits: 7)
                )
                prints["pair-\(index)-a"] = FeaturePrint(descriptor: Self.descriptor, elements: first)
                prints["pair-\(index)-b"] = FeaturePrint(descriptor: Self.descriptor, elements: second)

                // Distinct byte sizes, so the metadata bucket finds no exact-duplicate suspects
                // and the digest stage does no work. This measurement is about the sweep.
                items.append(Fixtures.item("pair-\(index)-a", bytes: 4_000_000 + Int64(index) * 37))
                items.append(Fixtures.item("pair-\(index)-b", bytes: 3_500_000 + Int64(index) * 41))
            }

            // The rest are photographs of unrelated things. Two random unit vectors in 768
            // dimensions sit about 2.0 apart in this squared metric; Vision's own unrelated
            // pairs measured 1.67 (`docs/OPPORTUNITIES.md` §9.2). Close enough that the early
            // exit in `proximity(within:)` gives up after a comparable number of elements,
            // which is the cost this is trying to measure honestly.
            for index in 0..<(count - pairCount * 2) {
                let id = "solo-\(index)"
                let seed = Self.scramble(UInt64(index) &+ 0xA11C_E000)
                hashes[id] = PerceptualHashes(dHash: seed, pHash: Self.scramble(seed))
                prints[id] = FeaturePrint(
                    descriptor: Self.descriptor,
                    elements: Self.unitVector(seed: UInt64(index) &* 0x2545_F491_4F6C_DD1D &+ 7)
                )
                items.append(Fixtures.item(id, bytes: 2_000_000 + Int64(index) * 53))
            }

            // The pile: one scene, photographed into `pile` copies that are all mutually
            // within the similar threshold. This is the "five thousand screenshots of the same
            // app screen" the neighbour cap was written for.
            if pile > 0 {
                let base = Self.unitVector(seed: 0xD15E_A5E0)
                for index in 0..<pile {
                    let id = "pile-\(index)"
                    let (_, copy) = Self.tilted(base, apart: 0.03, seed: UInt64(index) &+ 0xC0FFEE)
                    prints[id] = FeaturePrint(descriptor: Self.descriptor, elements: copy)
                    // Seven bits apart from one shared base, so the hashes agree with the
                    // prints about this being one pile rather than contradicting them.
                    let seed = Self.scramble(0x5C12_EE00)
                    hashes[id] = PerceptualHashes(
                        dHash: Self.flipping(seed, bits: index % 5),
                        pHash: Self.flipping(Self.scramble(seed), bits: index % 5)
                    )
                    items.append(
                        Fixtures.item(id, bytes: 1_200_000 + Int64(index) * 17, screenshot: true)
                    )
                }
            }

            self.items = items
            self.analyzer = PrintingAnalyzer(hashes: hashes, prints: withPrints ? prints : [:])
        }

        // MARK: Vector arithmetic

        static let descriptor = "vision.revision2"

        /// A deterministic random unit vector, dense in all 768 elements.
        ///
        /// Density is the point. The two-element vectors the matching tests use are correct
        /// about distance and wrong about cost: `proximity(within:)` exits as soon as the
        /// running sum passes the limit, and on a vector whose energy is all in element one
        /// that happens immediately. A measurement taken on those would flatter the engine.
        static func unitVector(seed: UInt64, count: Int = 768) -> [Float] {
            var rng = SplitMix64(seed: seed)
            var values = [Float](repeating: 0, count: count)
            var total = 0.0
            for index in 0..<count {
                // [-1, 1), from the top 53 bits so the low-order noise of the generator is not
                // what decides the vector.
                let unit = Double(rng.next() >> 11) / Double(1 << 53) * 2 - 1
                values[index] = Float(unit)
                total += unit * unit
            }
            let norm = Float(total.squareRoot())
            for index in 0..<count { values[index] /= norm }
            return values
        }

        /// `base`, and `base` rotated until it sits exactly `apart` away in the squared
        /// Euclidean the engine uses.
        ///
        /// For unit vectors, squared distance d gives cos θ = 1 − d/2. The rotation is into a
        /// random direction made orthogonal to `base`, so the difference is spread across all
        /// 768 elements rather than concentrated in one.
        static func tilted(_ base: [Float], apart: Double, seed: UInt64) -> ([Float], [Float]) {
            let cosine = 1 - apart / 2
            let sine = (1 - cosine * cosine).squareRoot()

            var perpendicular = unitVector(seed: seed, count: base.count)
            // Gram-Schmidt: strip the component along `base`, then renormalise.
            var projection = 0.0
            for index in base.indices { projection += Double(base[index]) * Double(perpendicular[index]) }
            var total = 0.0
            for index in base.indices {
                let value = Double(perpendicular[index]) - projection * Double(base[index])
                perpendicular[index] = Float(value)
                total += value * value
            }
            let norm = Float(total.squareRoot())
            for index in base.indices { perpendicular[index] /= norm }

            var rotated = [Float](repeating: 0, count: base.count)
            for index in base.indices {
                rotated[index] = Float(cosine) * base[index] + Float(sine) * perpendicular[index]
            }
            return (base, rotated)
        }

        static func scramble(_ value: UInt64) -> UInt64 {
            var z = value &+ 0x9E37_79B9_7F4A_7C15
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        static func flipping(_ value: UInt64, bits: Int) -> UInt64 {
            var result = value
            for bit in 0..<bits { result ^= (UInt64(1) << UInt64(bit)) }
            return result
        }
    }

    /// Hashes and prints, the way a Vision-backed analyzer answers.
    private final class PrintingAnalyzer: AssetAnalyzing, @unchecked Sendable {

        private let hashes: [String: PerceptualHashes]
        private let prints: [String: FeaturePrint]

        init(hashes: [String: PerceptualHashes], prints: [String: FeaturePrint]) {
            self.hashes = hashes
            self.prints = prints
        }

        func contentDigest(for item: MediaItem) async -> ContentDigestResult { .unavailable }

        func perceptualHashes(for item: MediaItem) async -> PerceptualHashes? { hashes[item.id] }

        func imageFingerprint(for item: MediaItem) async -> ImageFingerprint? {
            guard let hashes = hashes[item.id] else { return nil }
            return ImageFingerprint(hashes: hashes, featurePrint: prints[item.id])
        }
    }

    private func isPaired(_ result: ScanResult, _ first: String, _ second: String) -> Bool {
        result.groups.contains { $0.itemIDs.contains(first) && $0.itemIDs.contains(second) }
    }

    /// The heavy half of this file runs only when asked for.
    ///
    /// Measured: the pile at two thousand copies takes five minutes on its own, because every
    /// pair of a pile is *inside* the threshold and `proximity(within:)` therefore never exits
    /// early — it sums all 768 elements, 2.2 million times. That is a real number about the
    /// engine and a bad one to put in front of every `swift test`. The cheap correctness tests
    /// above stay on; the measurements run with `DUPESPACE_SCALE=1`.
    private func skipUnlessMeasuring() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DUPESPACE_SCALE"] == "1",
            "set DUPESPACE_SCALE=1 to run the scale measurements"
        )
    }

    // MARK: - Is it still right up there?

    /// Fifty planted pairs among five hundred photographs, and nothing else joined to them.
    ///
    /// The fixture this app was built on holds four groups. Everything below — the neighbour
    /// cap, the seed-first clustering, the tier assignment — has only ever been watched at that
    /// size, and a correctness claim at twenty-eight items is not one at five hundred.
    func testEveryPlantedPairIsFoundInALibraryOfFiveHundred() async throws {
        let corpus = Corpus(count: 500)
        let result = try await ScanPipeline(analyzer: corpus.analyzer, throttle: UnthrottledScan())
            .run(items: corpus.items)

        for index in 0..<corpus.pairCount {
            XCTAssertTrue(
                isPaired(result, "pair-\(index)-a", "pair-\(index)-b"),
                "pair \(index) was planted 0.03 apart and the similar limit is 0.20"
            )
        }
        XCTAssertEqual(
            result.groups.count,
            corpus.pairCount,
            "four hundred unrelated photographs should have formed no group at all"
        )
    }

    /// No unrelated photograph is dragged into a group by the sweep.
    ///
    /// Four hundred singletons is roughly a hundred and sixty thousand pairs of things that are
    /// not duplicates. A single false positive here is a photograph the app offers to delete.
    func testFourHundredUnrelatedPhotographsProduceNoCandidate() async throws {
        let corpus = Corpus(count: 500)
        let result = try await ScanPipeline(analyzer: corpus.analyzer, throttle: UnthrottledScan())
            .run(items: corpus.items)

        let solos = result.candidates.filter { $0.id.hasPrefix("solo-") }
        XCTAssertTrue(solos.isEmpty, "unrelated photographs offered for deletion: \(solos.map(\.id))")
    }

    /// A pile of the same screenshot, at three sizes: does it come back as one group?
    ///
    /// `maximumNeighboursPerItem` is 256 and the clusterer is seed-first rather than transitive
    /// (`DuplicateClusterer.similarGroups:69` takes a seed, claims its neighbours, and moves on),
    /// so this is where those two meet. A pile bigger than the cap cannot all be one seed's
    /// neighbours, and what happens then had never been run.
    ///
    /// Reachability is the assertion that matters and it is absolute: a copy in no group at all
    /// is a duplicate the app silently fails to find. The number of groups is recorded rather
    /// than demanded — see the table in `docs/STATE-OF-PLAY.md`.
    func testAPileOfOneScreenshotStaysReachableAboveTheNeighbourCap() async throws {
        try skipUnlessMeasuring()
        for pile in [300, 1_000, 2_000] {
            let corpus = Corpus(count: 100, pile: pile)
            let result = try await ScanPipeline(analyzer: corpus.analyzer, throttle: UnthrottledScan())
                .run(items: corpus.items)

            let pileGroups = result.groups.filter { $0.itemIDs.contains { $0.hasPrefix("pile-") } }
            let reached = Set(pileGroups.flatMap(\.itemIDs).filter { $0.hasPrefix("pile-") })
            let kept = pileGroups.count

            print("PILE \(pile) copies: \(kept) group(s), \(reached.count) reachable, "
                  + "\(pile - result.candidates.filter { $0.id.hasPrefix("pile-") }.count) kept")

            XCTAssertEqual(
                reached.count,
                pile,
                "\(pile) copies of one screenshot and \(pile - reached.count) of them were in no group"
            )
        }
    }

    /// A pile that fits under the cap comes back whole. Cheap enough to run every time, and it
    /// is the assertion that would catch a copy going missing entirely.
    func testAPileOfThreeHundredCopiesIsOneGroup() async throws {
        let corpus = Corpus(count: 100, pile: 300)
        let result = try await ScanPipeline(analyzer: corpus.analyzer, throttle: UnthrottledScan())
            .run(items: corpus.items)

        let pileGroups = result.groups.filter { $0.itemIDs.contains { $0.hasPrefix("pile-") } }
        let reached = Set(pileGroups.flatMap(\.itemIDs).filter { $0.hasPrefix("pile-") })

        XCTAssertEqual(reached.count, 300, "no copy may be left out of every group")
        XCTAssertEqual(pileGroups.count, 1, "three hundred is under the 256 cap once back-edges count")
    }

    /// How many copies survive a clean-up of one pile.
    ///
    /// **This test records a defect.** Measured on 15 September 2026: a thousand copies of one
    /// screenshot come back as five groups, and every group keeps one, so ticking everything the
    /// app offers leaves **five** identical screenshots rather than one. Two thousand copies
    /// leave ten. Nothing is lost — every copy is reachable and offered — but the promise on the
    /// rung is "keep one", and above the cap the app quietly keeps one per two hundred.
    ///
    /// Cause: `ScanPipeline.maximumNeighboursPerItem` drops edges past 256 to bound memory, and
    /// `DuplicateClusterer.similarGroups` is seed-first rather than transitive — it takes one
    /// seed's neighbours and moves on. Above the cap no single seed can reach the whole pile.
    ///
    /// `XCTExpectFailure` rather than a changed expectation: the assertion below is what the app
    /// promises, and the day somebody makes the clustering reach further this test has to go
    /// red so the fix is noticed.
    func testHowManyCopiesSurviveCleaningOnePile() async throws {
        try skipUnlessMeasuring()
        XCTExpectFailure("a pile above the neighbour cap fragments — see docs/STATE-OF-PLAY.md")

        let corpus = Corpus(count: 100, pile: 1_000)
        let result = try await ScanPipeline(analyzer: corpus.analyzer, throttle: UnthrottledScan())
            .run(items: corpus.items)

        let offered = result.candidates.filter { $0.id.hasPrefix("pile-") }.count
        XCTAssertEqual(1_000 - offered, 1, "a thousand copies of one screenshot should leave one")
    }

    /// The stop button still works while the sweep is running.
    ///
    /// `edges` checks cancellation every 128 items. At two thousand items the sweep is the
    /// longest thing the app does, and a cancel that is not honoured there is a spinner that
    /// cannot be dismissed.
    func testTheSweepIsCancellableAtScale() async throws {
        let corpus = Corpus(count: 2_000)
        let task = Task {
            try await ScanPipeline(analyzer: corpus.analyzer, throttle: UnthrottledScan())
                .run(items: corpus.items)
        }
        // Long enough to be inside the sweep, short enough that the test does not wait for it.
        try await Task.sleep(for: .milliseconds(120))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("a cancelled scan returned a result")
        } catch is CancellationError {
            // What should happen.
        }
    }

    // MARK: - What does it cost?

    /// Wall time and counts at five hundred, a thousand and two thousand items.
    ///
    /// Not an assertion about speed — a number printed, so the table in `docs/STATE-OF-PLAY.md`
    /// comes from a run rather than from an estimate. The only assertion is a ceiling loose
    /// enough that only a catastrophic regression trips it.
    func testTheCostOfTheSweep() async throws {
        try skipUnlessMeasuring()
        for count in [500, 1_000, 2_000] {
            for withPrints in [true, false] {
                let corpus = Corpus(count: count, withPrints: withPrints)
                let started = ContinuousClock.now
                let result = try await ScanPipeline(analyzer: corpus.analyzer, throttle: UnthrottledScan())
                    .run(items: corpus.items)
                let elapsed = ContinuousClock.now - started

                let pairs = count * (count - 1) / 2
                print(
                    "SCALE \(count) items, prints \(withPrints ? "on " : "off"): "
                    + "\(elapsed) for \(pairs) pairs, "
                    + "\(result.groups.count) groups, \(result.candidates.count) candidates"
                )

                XCTAssertEqual(result.groups.count, corpus.pairCount, "\(count) items, prints \(withPrints)")
                XCTAssertLessThan(
                    elapsed,
                    .seconds(180),
                    "\(count) items took \(elapsed) — this is a ceiling for catastrophe, not a target"
                )
            }
        }
    }
}
