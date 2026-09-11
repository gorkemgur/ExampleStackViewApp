import Foundation

/// Size of the square the DCT-based hash operates on.
private let dctSize = 32

/// `cos(pi * (i + 0.5) * k / N)` for every (k, i) pair, computed once.
private let dctCosTable: [Double] = {
    var table = [Double](repeating: 0, count: dctSize * dctSize)
    for k in 0..<dctSize {
        for i in 0..<dctSize {
            table[k * dctSize + i] = cos(Double.pi * (Double(i) + 0.5) * Double(k) / Double(dctSize))
        }
    }
    return table
}()

/// 64-bit perceptual fingerprints.
///
/// Two hashes are computed per image because they fail differently: `dHash` tracks local
/// gradients and survives brightness shifts, `pHash` tracks low-frequency structure and
/// survives cropping-free rescaling and heavy JPEG recompression. A candidate pair only has
/// to be close under *one* of them to reach the (far more expensive) verification stage.
public enum PerceptualHasher {

    /// Difference hash: compare each pixel with its right-hand neighbour on a 9x8 thumbnail.
    public static func dHash(_ image: GrayImage) -> UInt64 {
        let small = image.resized(width: 9, height: 8)
        var bits: UInt64 = 0
        var index = 0
        for y in 0..<8 {
            for x in 0..<8 {
                if small.pixel(x: x, y: y) > small.pixel(x: x + 1, y: y) {
                    bits |= (UInt64(1) << (63 - index))
                }
                index += 1
            }
        }
        return bits
    }

    /// Perceptual hash: 2-D DCT of a 32x32 thumbnail, thresholded against the median of the
    /// low-frequency 8x8 block (DC excluded from the median so overall exposure does not
    /// drag the threshold around).
    public static func pHash(_ image: GrayImage) -> UInt64 {
        let small = image.resized(width: dctSize, height: dctSize)

        var matrix = [Double](repeating: 0, count: dctSize * dctSize)
        for index in 0..<(dctSize * dctSize) {
            matrix[index] = Double(small.pixels[index])
        }

        let coefficients = dct2D(matrix)

        var block = [Double]()
        block.reserveCapacity(64)
        for y in 0..<8 {
            for x in 0..<8 {
                block.append(coefficients[y * dctSize + x])
            }
        }

        let threshold = median(of: Array(block.dropFirst()))

        var bits: UInt64 = 0
        for (index, value) in block.enumerated() where value > threshold {
            bits |= (UInt64(1) << (63 - index))
        }
        return bits
    }

    // MARK: - DCT

    private static func dct1D(_ input: [Double]) -> [Double] {
        var output = [Double](repeating: 0, count: dctSize)
        let dcScale = (1.0 / Double(dctSize)).squareRoot()
        let acScale = (2.0 / Double(dctSize)).squareRoot()

        for k in 0..<dctSize {
            var sum = 0.0
            let rowStart = k * dctSize
            for i in 0..<dctSize {
                sum += input[i] * dctCosTable[rowStart + i]
            }
            output[k] = sum * (k == 0 ? dcScale : acScale)
        }
        return output
    }

    private static func dct2D(_ matrix: [Double]) -> [Double] {
        precondition(matrix.count == dctSize * dctSize)
        var intermediate = [Double](repeating: 0, count: dctSize * dctSize)

        for row in 0..<dctSize {
            let start = row * dctSize
            let transformed = dct1D(Array(matrix[start..<(start + dctSize)]))
            for column in 0..<dctSize {
                intermediate[start + column] = transformed[column]
            }
        }

        var result = [Double](repeating: 0, count: dctSize * dctSize)
        var column = [Double](repeating: 0, count: dctSize)
        for columnIndex in 0..<dctSize {
            for row in 0..<dctSize {
                column[row] = intermediate[row * dctSize + columnIndex]
            }
            let transformed = dct1D(column)
            for row in 0..<dctSize {
                result[row * dctSize + columnIndex] = transformed[row]
            }
        }
        return result
    }

    private static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}
