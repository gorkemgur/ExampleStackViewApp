import Foundation

/// A plain 8-bit grayscale buffer. The perceptual hashers work on this rather than on
/// `CGImage` so they can be exercised with synthetic input in unit tests.
public struct GrayImage: Sendable, Equatable {

    public let width: Int
    public let height: Int
    /// Row-major, `width * height` samples.
    public let pixels: [UInt8]

    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    @inlinable
    public func pixel(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }

    /// Area-average resize. Downscaling averages every source pixel that falls inside the
    /// destination pixel's footprint, which is what makes the hashes stable across the
    /// resampling a messaging app applies when it recompresses a photo.
    public func resized(width newWidth: Int, height newHeight: Int) -> GrayImage {
        precondition(newWidth > 0 && newHeight > 0, "resize target must be positive")
        if newWidth == width && newHeight == height { return self }

        var output = [UInt8](repeating: 0, count: newWidth * newHeight)
        let xRatio = Double(width) / Double(newWidth)
        let yRatio = Double(height) / Double(newHeight)

        for y in 0..<newHeight {
            let sourceY0 = min(Int(Double(y) * yRatio), height - 1)
            var sourceY1 = Int(Double(y + 1) * yRatio)
            if sourceY1 <= sourceY0 { sourceY1 = sourceY0 + 1 }
            sourceY1 = min(sourceY1, height)

            for x in 0..<newWidth {
                let sourceX0 = min(Int(Double(x) * xRatio), width - 1)
                var sourceX1 = Int(Double(x + 1) * xRatio)
                if sourceX1 <= sourceX0 { sourceX1 = sourceX0 + 1 }
                sourceX1 = min(sourceX1, width)

                var sum = 0
                var count = 0
                for sy in sourceY0..<sourceY1 {
                    let rowStart = sy * width
                    for sx in sourceX0..<sourceX1 {
                        sum += Int(pixels[rowStart + sx])
                        count += 1
                    }
                }
                output[y * newWidth + x] = UInt8(sum / max(count, 1))
            }
        }

        // Force-unwrap is safe: dimensions and buffer length are constructed together.
        return GrayImage(width: newWidth, height: newHeight, pixels: output)!
    }
}
