import XCTest
import UIKit
@testable import DupeSpace
import DupeCore

/// The gate that decides whether this machine's Vision is trusted with a deletion.
///
/// It exists because of a measurement, not a worry: on an iOS 18.6 simulator the feature print
/// request succeeds — right length, right element type, 3072 bytes — and returns *the same
/// vector for every image*. Two deliberately opposite pictures came back 0.0000032 apart, which
/// is well inside the threshold for "identical copy". Without this gate the app would have
/// offered every photograph in a library as a duplicate of every other one, on a screen whose
/// whole job is deleting things.
final class VisionGateTests: XCTestCase {

    func testTheTwoProbeImagesAreGenuinelyDifferentPictures() throws {
        let (light, dark) = try XCTUnwrap(VisionFeaturePrinter.probeImages())

        // Measured with the engine's own hashes, which work everywhere — so this holds on a
        // simulator, in CI and on a phone. If someone later "simplifies" the probes into two
        // images that are actually alike, the gate would pass on a broken platform and the
        // protection would be gone with every test still green.
        let first = try XCTUnwrap(GrayImageRenderer.render(light))
        let second = try XCTUnwrap(GrayImageRenderer.render(dark))
        let bits = (PerceptualHasher.dHash(first) ^ PerceptualHasher.dHash(second)).nonzeroBitCount

        XCTAssertGreaterThan(bits, 20, "the probes have to be obviously different to anything that looks at them")
    }

    func testTheFloorIsTheThresholdTheEngineActuallyUses() {
        XCTAssertEqual(
            VisionFeaturePrinter.discriminationFloor,
            ScanConfiguration.default.featurePrintSimilarDistance,
            "a model that puts the two probes closer than 'worth showing you' is telling us they are the same picture"
        )
    }

    /// Whatever this platform is, one of two things has to be true, and both are fine: either
    /// Vision discriminates and the app uses prints, or it does not and the app uses hashes.
    /// What must never happen is prints being produced by a model that cannot tell the probes
    /// apart.
    func testAPlatformThatFailsTheProbeProducesNoPrintsAtAll() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        }.cgImage!

        let print = VisionFeaturePrinter.featurePrint(of: image)

        if VisionFeaturePrinter.isUsable {
            XCTAssertNotNil(print, "the gate is open, so the printer has to produce something")
        } else {
            XCTAssertNil(print, "the gate is shut and a vector from a model that cannot discriminate is worse than none")
        }
    }
}
