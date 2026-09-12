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

/// A 32x64 grayscale reading of a frame, cheap enough to take on every one of them.
func digest(_ image: CGImage) -> [UInt8]? {
    // Half the output's own size. A 32x64 reading was the first attempt and it is too coarse
    // to see a progress ring turning inside a 104-point circle on a 695-point screen — it
    // called two-thirds of the real motion in these clips static.
    let width = 160, height = 348
    var pixels = [UInt8](repeating: 0, count: width * height)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
}

func distance(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 255 }
    var total = 0
    for index in a.indices { total += abs(Int(a[index]) - Int(b[index])) }
    return Double(total) / Double(a.count)
}

// A screen recording of an app being driven is mostly a still picture: the walk waits on
// `describe-all`, which costs a second or two a call, and every one of those seconds is in the
// recording. Filmed straight through, a nineteen-second tour came out at thirty-six seconds
// with twenty-seven moving frames in four hundred and fifty-two.
//
// So a frame that is the same as the last one kept is not written. Its time is added to that
// frame's delay instead, up to `maxHold` — the pause stays legible as a pause and stops being
// dead air. Motion is untouched and plays at the speed it was recorded at, which is the whole
// point: this is an edit, not a time-lapse.
let staticThreshold = 0.08       // mean grayscale levels, out of 255
let maxHold = 0.7                // seconds any one pause is allowed to keep

var pendingImage: CGImage?
var pendingDelay = 0.0
var lastDigest: [UInt8]?
var written = 0
var skipped = 0

func flush() {
    guard let image = pendingImage else { return }
    let held = min(max(pendingDelay, delay), maxHold)
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFUnclampedDelayTime: held,
            kCGImagePropertyGIFDelayTime: held
        ]
    ] as CFDictionary)
    written += 1
    pendingImage = nil
    pendingDelay = 0
}

for index in 0..<frameCount {
    let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
    guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
    let current = digest(image)

    if let current, let lastDigest, distance(current, lastDigest) < staticThreshold {
        // Same picture. Hold the one already waiting rather than writing this one.
        pendingDelay += delay
        skipped += 1
        continue
    }

    flush()
    pendingImage = image
    pendingDelay = delay
    lastDigest = current
}
flush()

guard written > 1, CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("only \(written) frame(s) came back from \(input.lastPathComponent)\n".utf8))
    exit(1)
}

let attributes = try? FileManager.default.attributesOfItem(atPath: output.path)
let bytes = (attributes?[.size] as? Int) ?? 0
print("\(output.lastPathComponent): \(written) frames kept, \(skipped) static dropped, \(String(format: "%.1f", seconds))s recorded, \(bytes / 1024) KB")
