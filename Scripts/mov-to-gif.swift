#!/usr/bin/env swift
//
// Turn a simulator recording into an animated GIF, with what every Mac already has.
//
//   swift Scripts/mov-to-gif.swift in.mov out.gif [width] [fps]
//
// The runners have no ffmpeg, and installing one to make a preview would cost more than the
// preview is worth — that is why the .mov has been committed unconverted since the recorder
// was written. But AVFoundation reads the frames and ImageIO writes the GIF, and both ship
// with the operating system, so there was never anything to install.
//
// `requestedTimeToleranceBefore/After = .zero` matters: without it the generator happily hands
// back the same keyframe for several consecutive requests and the GIF stutters where the
// recording does not.
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: mov-to-gif.swift in.mov out.gif [width] [fps]\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let targetWidth = arguments.count > 3 ? Int(arguments[3]) ?? 320 : 320
let fps = arguments.count > 4 ? Double(arguments[4]) ?? 12 : 12

let asset = AVURLAsset(url: input)

let semaphore = DispatchSemaphore(value: 0)
var duration = CMTime.zero
var loadError: Error?
Task {
    do { duration = try await asset.load(.duration) } catch { loadError = error }
    semaphore.signal()
}
semaphore.wait()

if let loadError {
    FileHandle.standardError.write(Data("cannot read \(input.lastPathComponent): \(loadError)\n".utf8))
    exit(1)
}

let seconds = CMTimeGetSeconds(duration)
guard seconds.isFinite, seconds > 0 else {
    FileHandle.standardError.write(Data("\(input.lastPathComponent) has no duration\n".utf8))
    exit(1)
}

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
// Height unconstrained, so the width is what decides the scale.
generator.maximumSize = CGSize(width: targetWidth, height: 10_000)

let frameCount = max(Int(seconds * fps), 2)
let delay = 1.0 / fps

guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    UTType.gif.identifier as CFString,
    frameCount,
    nil
) else {
    FileHandle.standardError.write(Data("cannot write \(output.path)\n".utf8))
    exit(1)
}

CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
] as CFDictionary)

let frameProperties = [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay, kCGImagePropertyGIFDelayTime: delay]
] as CFDictionary

var written = 0
for index in 0..<frameCount {
    let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
    guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
    CGImageDestinationAddImage(destination, image, frameProperties)
    written += 1
}

guard written > 1, CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("only \(written) frame(s) came back from \(input.lastPathComponent)\n".utf8))
    exit(1)
}

let attributes = try? FileManager.default.attributesOfItem(atPath: output.path)
let bytes = (attributes?[.size] as? Int) ?? 0
print("\(output.lastPathComponent): \(written) frames, \(String(format: "%.1f", seconds))s, \(bytes / 1024) KB")
