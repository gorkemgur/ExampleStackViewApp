#!/usr/bin/env swift
//
// Prints one line per video frame: its timestamp, then a 16x16 grid of average brightness.
//
// This exists because the CI runner has no ffmpeg and installing it to answer one question
// costs more than the question is worth. Every machine that can build this app has
// AVFoundation, which reads the frames directly.
//
// A grid rather than a hash, because a hash cannot tell motion from noise. The recording is
// H.264: two decodes of an identical screen differ by a pixel value here and there, so every
// frame hashes differently and a still screen would be reported as animating. Averaged over a
// sixteenth of the screen that noise disappears, while anything that actually moves does not.

import AVFoundation
import Foundation

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: frame-digests.swift <video>\n".utf8))
    exit(64)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)

guard let track = asset.tracks(withMediaType: .video).first else {
    FileHandle.standardError.write(Data("no video track in \(url.lastPathComponent)\n".utf8))
    exit(65)
}

let reader: AVAssetReader
do {
    reader = try AVAssetReader(asset: asset)
} catch {
    FileHandle.standardError.write(Data("cannot read \(url.lastPathComponent): \(error)\n".utf8))
    exit(66)
}

let output = AVAssetReaderTrackOutput(
    track: track,
    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
)
reader.add(output)
reader.startReading()

let GRID = 16

/// Average brightness per cell of a 16x16 grid over the frame.
func signature(of buffer: CVPixelBuffer) -> [Int] {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let bytes = base.assumingMemoryBound(to: UInt8.self)

    var totals = [Int](repeating: 0, count: GRID * GRID)
    var counts = [Int](repeating: 0, count: GRID * GRID)

    // Every fourth pixel in both directions: enough samples per cell for the average to be
    // stable, a sixteenth of the work.
    var y = 0
    while y < height {
        let cellY = min(y * GRID / height, GRID - 1)
        var x = 0
        while x < width {
            let offset = y * stride + x * 4
            // BGRA, weighted the way the eye weights them.
            let blue = Int(bytes[offset])
            let green = Int(bytes[offset + 1])
            let red = Int(bytes[offset + 2])
            let cell = cellY * GRID + min(x * GRID / width, GRID - 1)
            totals[cell] += (red * 299 + green * 587 + blue * 114) / 1000
            counts[cell] += 1
            x += 4
        }
        y += 4
    }

    return (0..<(GRID * GRID)).map { counts[$0] > 0 ? totals[$0] / counts[$0] : 0 }
}

while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
    guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
    let cells = signature(of: buffer).map { String(format: "%02x", min(max($0, 0), 255)) }
    print(String(format: "%.4f ", seconds) + cells.joined())
}

if reader.status == .failed {
    FileHandle.standardError.write(Data("reader failed: \(reader.error as Any)\n".utf8))
    exit(67)
}
