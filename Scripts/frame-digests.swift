#!/usr/bin/env swift
//
// Prints one line per video frame: its timestamp and a digest of its pixels.
//
// This exists because the CI runner has no ffmpeg and installing it to answer one question
// costs more than the question is worth. Every machine that can build this app has
// AVFoundation, which reads the frames directly.
//
// The digest samples the buffer rather than hashing every byte: two frames of a moving
// animation differ in thousands of places, so a sparse sample separates them just as well as a
// full one and costs a fraction as much.

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

/// FNV-1a over a sparse sample of the frame.
func digest(of buffer: CVPixelBuffer) -> UInt64 {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
    let size = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
    let bytes = base.assumingMemoryBound(to: UInt8.self)

    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    var index = 0
    // A prime stride so the sample never lines up with the row width and reads one column.
    while index < size {
        hash = (hash ^ UInt64(bytes[index])) &* 0x1000_0000_01b3
        index += 997
    }
    return hash
}

while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
    guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
    print(String(format: "%.4f %016llx", seconds, digest(of: buffer)))
}

if reader.status == .failed {
    FileHandle.standardError.write(Data("reader failed: \(reader.error as Any)\n".utf8))
    exit(67)
}
