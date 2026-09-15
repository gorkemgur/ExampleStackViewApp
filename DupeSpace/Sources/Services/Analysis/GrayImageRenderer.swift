import CoreGraphics
import DupeCore

/// Draws a `CGImage` into a fixed square 8-bit grayscale buffer.
///
/// The square is deliberate rather than aspect-preserving: two copies of the same photo share
/// an aspect ratio, so they stretch identically and their fingerprints still match, while a
/// fixed buffer size keeps the hashing cost constant no matter what came out of the library.
enum GrayImageRenderer {

    static let renderSize = 64

    static func render(_ image: CGImage, size: Int = renderSize) -> GrayImage? {
        guard size > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: size * size)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: size,
                    height: size,
                    bitsPerComponent: 8,
                    bytesPerRow: size,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }

        guard drawn else { return nil }
        return GrayImage(width: size, height: size, pixels: pixels)
    }
}
