import Foundation

/// Where two copies actually differ, as a coarse grid of magnitudes.
///
/// `docs/CONCEPT.md` has promised a pixel-difference heat map since the first day of the
/// project — it is the second of the five things listed as setting this app apart from Apple's
/// own Duplicates: *neden eşleşti, görünür*, the match is shown rather than asserted. The wipe
/// comparator and the measurements table were built; this was not.
///
/// Pure, and in the core package, because the drawing is trivial and the arithmetic is what can
/// lie. A heat map that says two copies differ where they do not is worse than no heat map: it
/// is the app inventing evidence for a deletion.
///
/// Coarse on purpose. The inputs are the same 64×64 grayscale buffers the perceptual hashes are
/// taken from, so the grid costs nothing extra and — more importantly — shows the difference
/// *the engine actually saw*. A full-resolution diff would show differences the matcher never
/// considered, which would make the picture a second opinion rather than an explanation.
public struct DifferenceGrid: Sendable, Equatable {

    public let size: Int
    /// Row-major, 0 where the two copies agree and 1 at the largest difference in this pair.
    public let cells: [Double]

    /// The largest raw difference before normalising, as a fraction of full scale. Zero means
    /// the two buffers are identical, and it is what decides whether there is anything worth
    /// drawing at all.
    public let peak: Double

    public init(size: Int, cells: [Double], peak: Double) {
        self.size = size
        self.cells = cells
        self.peak = peak
    }

    public var isEmpty: Bool { cells.isEmpty }

    /// True when the two copies are close enough that a heat map would be noise dressed as
    /// evidence. Below this the view says every pixel the scan compared is the same, rather
    /// than drawing a grid of rounding error.
    public var isBelowNoiseFloor: Bool { peak < 0.02 }

    public func cell(x: Int, y: Int) -> Double {
        guard x >= 0, y >= 0, x < size, y < size else { return 0 }
        return cells[y * size + x]
    }

    /// Builds the grid from the two grayscale buffers the fingerprints were taken from.
    ///
    /// Normalised to this pair's own peak rather than to full scale, deliberately. Two copies
    /// that differ by a hair still differ *somewhere*, and the question this picture answers is
    /// "where is this copy different" — not "how different is it", which the table underneath
    /// answers in numbers. Without the normalisation almost every pair would draw a uniformly
    /// black square, and `peak` is carried alongside so the view can say when there is nothing
    /// to show at all.
    public static func between(_ a: GrayImage, _ b: GrayImage, size: Int = 16) -> DifferenceGrid? {
        guard
            size > 0,
            a.width == b.width,
            a.height == b.height
        else {
            return nil
        }

        var sums = [Double](repeating: 0, count: size * size)
        var counts = [Int](repeating: 0, count: size * size)

        for y in 0..<a.height {
            let cellY = min(y * size / a.height, size - 1)
            for x in 0..<a.width {
                let cellX = min(x * size / a.width, size - 1)
                let index = y * a.width + x
                let delta = abs(Int(a.pixels[index]) - Int(b.pixels[index]))
                let cell = cellY * size + cellX
                sums[cell] += Double(delta) / 255
                counts[cell] += 1
            }
        }

        var averages = [Double](repeating: 0, count: size * size)
        for index in 0..<averages.count where counts[index] > 0 {
            averages[index] = sums[index] / Double(counts[index])
        }

        let peak = averages.max() ?? 0
        guard peak > 0 else {
            return DifferenceGrid(size: size, cells: averages, peak: 0)
        }

        return DifferenceGrid(size: size, cells: averages.map { $0 / peak }, peak: peak)
    }
}
