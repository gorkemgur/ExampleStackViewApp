import CoreGraphics
import Foundation
import Vision
import DupeCore

/// Turns a decoded image into the vector the engine compares.
///
/// The measurement that put this here is in `docs/OPPORTUNITIES.md` §9.1: against dHash/pHash a
/// 30 % crop scores 34 of 64 bits, which is exactly what a photograph of something else scores.
/// Here the same two pairs are 0.1036 and 1.6697 apart.
enum VisionFeaturePrinter {

    /// Revision 2, pinned, and not "whatever is newest".
    ///
    /// Two revisions produce vectors that mean different things — Vision throws rather than
    /// comparing them, and revision 1 is 2048 elements against revision 2's 768. Revision 2 is
    /// also the cheaper of the two by a factor of about seven (20.9 ms against 139.6 ms).
    /// Taking the newest available would silently invalidate every cached vector on the first
    /// OS release that adds one, and the app would find nothing while looking perfectly healthy.
    static let revision = VNGenerateImageFeaturePrintRequestRevision2

    /// Part of the comparability contract, not a rendering preference: the *same* image scored
    /// against itself with `scaleFill` on one side and `scaleFit` on the other comes out 0.452
    /// apart, which is larger than most "these are different pictures" thresholds.
    ///
    /// `scaleFit` rather than `centerCrop` because the whole frame has to reach the model. A
    /// centre crop throws away the edges, and the edges are where a re-export, a letterbox and
    /// a screenshot differ from the original.
    static let cropAndScale: VNImageCropAndScaleOption = .scaleFit

    /// The one decode size everything uses. Measured: the same pair scores 0.143 at one decode
    /// size and 0.037 at another, so two halves of this app decoding at two sizes would fail to
    /// match the same photograph against itself — the bug `STATE-OF-PLAY.md` §1 already records
    /// once, in the perceptual hashes, under the name "two downsamplers, one matcher".
    static let decodeSize = GrayImageRenderer.renderSize * 4

    /// What produced a vector, said in full.
    ///
    /// Vision hands back its own `originatingRequestDescriptor`, and it names only the request
    /// and the revision. Our contract is wider than that: change the crop option or the decode
    /// size and the vectors stop being comparable while Vision's descriptor stays identical.
    /// So the descriptor is ours, it carries everything that can move, and `FeaturePrint`
    /// refusing to compare across descriptors then means what it says.
    static let descriptor = "vision.fp.r\(VNGenerateImageFeaturePrintRequestRevision2).scaleFit.\(GrayImageRenderer.renderSize * 4)"

    /// `nil` when Vision cannot describe this image, which is not an error worth surfacing: the
    /// item keeps its two hashes and is matched on those.
    ///
    /// Two attempts, and the second one is why anything here can be tested at all. Measured on
    /// an iOS 18.6 simulator: the default compute device is `Apple iOS simulator GPU`, and
    /// asking it for a feature print throws `Failed to create espresso context` — every image,
    /// every time. So the *entire* feature print path was silently absent on every simulator,
    /// which is every CI job this repository runs and every test anyone writes short of holding
    /// a phone. Pinning the request to the CPU device makes it work there: 768 elements, float,
    /// 3072 bytes, exactly the shape `docs/OPPORTUNITIES.md` §9.2 records.
    ///
    /// The fallback is remembered rather than repeated, because a library is fifty thousand
    /// images and a throw per image is fifty thousand throws.
    static func featurePrint(of image: CGImage) -> FeaturePrint? {
        guard Gate.isOpen else { return nil }
        return produce(image)
    }

    private static func produce(_ image: CGImage) -> FeaturePrint? {
        if Fallback.isNeeded {
            return attempt(image, pinningCPU: true)
        }
        if let print = attempt(image, pinningCPU: false) {
            return print
        }
        guard let print = attempt(image, pinningCPU: true) else { return nil }
        Fallback.remember()
        return print
    }

    // MARK: - Proving the model discriminates before trusting it with a deletion

    /// Whether Vision on *this* machine can tell two obviously different pictures apart.
    ///
    /// This is not defensive programming for its own sake. Measured on an iOS 18.6 simulator
    /// with the request pinned to the CPU device — the only way it runs there at all — Vision
    /// returns a vector for every image, of the right length and the right type, and the
    /// vectors are **all the same one**: a teal frame with an orange disc and a black frame
    /// with a white disc came back 0.0000032 apart, where two different photographs should be
    /// about 1.67. Every element agreed to four decimal places.
    ///
    /// A number that small is not "these are similar". It is below the near-exact threshold, so
    /// the matcher would have paired every photograph in the library with every other one and
    /// pre-ticked them as identical copies. The app's first rule is that it must never delete
    /// the wrong photograph, and a silently degenerate model is the most direct way to break it
    /// — the API succeeds, the shape is right, and nothing downstream can tell.
    ///
    /// So the model is asked to prove itself once per process, on two images this file draws
    /// itself, and it is not used at all unless it passes. Failing that costs the crop-finding
    /// the print was added for; it does not cost correctness, because the engine still has both
    /// hashes and the behaviour is the one that shipped before any of this existed.
    static var isUsable: Bool { Gate.isOpen }

    /// Two pictures with nothing in common: one is a smooth gradient with no edges anywhere,
    /// the other is a hard checkerboard with an edge every few pixels. Nothing that looks at
    /// images — a model, a hash, a person — could call these the same, which is the property
    /// the gate needs and the property `VisionGateTests` pins.
    static func probeImages() -> (CGImage, CGImage)? {
        guard let smooth = drawGradient(), let sharp = drawCheckerboard() else { return nil }
        return (smooth, sharp)
    }

    private static func context() -> CGContext? {
        CGContext(
            data: nil,
            width: decodeSize,
            height: decodeSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
    }

    private static func drawGradient() -> CGImage? {
        guard let context = context() else { return nil }
        let side = decodeSize
        for row in 0..<side {
            let value = CGFloat(row) / CGFloat(side - 1)
            context.setFillColor(red: value, green: value * 0.7, blue: 1 - value, alpha: 1)
            context.fill(CGRect(x: 0, y: row, width: side, height: 1))
        }
        return context.makeImage()
    }

    private static func drawCheckerboard() -> CGImage? {
        guard let context = context() else { return nil }
        let side = decodeSize
        let square = side / 8
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        for row in 0..<8 {
            for column in 0..<8 where (row + column) % 2 == 0 {
                context.fill(
                    CGRect(x: column * square, y: row * square, width: square, height: square)
                )
            }
        }
        return context.makeImage()
    }

    /// The distance two prints must clear before this platform's Vision is believed. Set at the
    /// engine's own "worth showing you" threshold: a model that puts these two inside it would
    /// be telling the app they are the same photograph.
    static let discriminationFloor = 0.2

    private enum Gate {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var answer: Bool?

        static var isOpen: Bool {
            lock.lock(); defer { lock.unlock() }
            if let answer { return answer }
            let verdict = prove()
            answer = verdict
            return verdict
        }

        private static func prove() -> Bool {
            guard
                let (light, dark) = probeImages(),
                let first = produce(light),
                let second = produce(dark),
                let distance = first.distance(to: second)
            else {
                return false
            }
            return distance > discriminationFloor
        }
    }

    /// Whether this machine needs the CPU device. One answer for the process, taken from the
    /// first image that needed it.
    private enum Fallback {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var needed = false

        static var isNeeded: Bool {
            lock.lock(); defer { lock.unlock() }
            return needed
        }

        static func remember() {
            lock.lock(); defer { lock.unlock() }
            needed = true
        }
    }

    private static func attempt(_ image: CGImage, pinningCPU: Bool) -> FeaturePrint? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = revision
        request.imageCropAndScaleOption = cropAndScale

        if pinningCPU, let stages = try? request.supportedComputeStageDevices {
            for (stage, devices) in stages {
                guard let cpu = devices.first(where: { if case .cpu = $0 { return true } else { return false } }) else {
                    continue
                }
                request.setComputeDevice(cpu, for: stage)
            }
        }

        // Orientation is not passed here on purpose. Every caller decodes through a path that
        // has already applied EXIF orientation — `kCGImageSourceCreateThumbnailWithTransform`
        // on the folder side, `PHImageManager` on the library side — so the pixels handed over
        // are upright. Measured: a 90-degree rotation scores 1.0434 unrotated and 0.0001 once
        // the orientation is applied, so this is the difference between finding a rotated copy
        // and calling it a different photograph.
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }

        guard
            let observation = request.results?.first as? VNFeaturePrintObservation,
            observation.elementType == .float,
            observation.elementCount > 0
        else {
            return nil
        }

        let elements = observation.data.withUnsafeBytes { raw -> [Float] in
            // `elementCount` is Vision's claim; the buffer is the fact. Reading the claim past
            // the end of the fact is the kind of crash that only happens on someone else's
            // photograph.
            let available = raw.count / MemoryLayout<Float>.size
            return Array(raw.bindMemory(to: Float.self).prefix(min(observation.elementCount, available)))
        }

        guard !elements.isEmpty else { return nil }
        return FeaturePrint(descriptor: descriptor, elements: elements)
    }
}
