#!/usr/bin/env swift
//
// Turn a simulator recording into an animated GIF of a given length, with what every Mac
// already has.
//
//   swift Scripts/mov-to-gif.swift in.mov out.gif [width] [fps] [maxSeconds] [maxFrames]
//
// The runners have no ffmpeg, and installing one to make a preview would cost more than the
// preview is worth — which is why the .mov went unconverted for so long. But AVFoundation
// reads the frames and ImageIO writes the GIF, and both ship with the operating system.
//
// THE EDIT. A screen recording of an app being driven is mostly a still picture: the walk waits
// on `describe-all`, and every one of those seconds is in the recording. So a frame that is the
// same as the last one kept is not written; its time is added to that frame's delay instead,
// capped, and a pause stays legible as a pause without being dead air. Motion is untouched and
// plays at the speed it was recorded at. This is an edit, not a time-lapse.
//
// AND THE LENGTH IS DECIDED HERE. Two attempts at capping the tour from inside the walk both
// missed — the budget bought the pauses and not the taps, the waits or the swipes, and the
// clips came back at thirty-six seconds and then at seventy-three. The recorder cannot know how
// long a runner will take. This can: it measures what it has, and raises the bar for what counts
// as motion until the result fits. A GIF nobody waits to load is worth as little as one nobody
// watches to the end.
//
// `requestedTimeToleranceBefore/After = .zero` matters throughout: without it the generator
// hands back the same keyframe for several consecutive requests and the result stutters where
// the recording does not.
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(
        Data("usage: mov-to-gif.swift in.mov out.gif [width] [fps] [maxSeconds] [maxFrames]\n".utf8)
    )
    exit(2)
}

let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let targetWidth = arguments.count > 3 ? Int(arguments[3]) ?? 320 : 320
let fps = arguments.count > 4 ? Double(arguments[4]) ?? 12 : 12
let maxSeconds = arguments.count > 5 ? Double(arguments[5]) ?? 18 : 18
let maxFrames = arguments.count > 6 ? Int(arguments[6]) ?? 200 : 200

/// How long any one pause may keep.
///
/// Swept against the real recordings, because it is the whole of the trade: a pause that keeps
/// for 0.4s spends the eighteen-second budget on stillness and leaves 47 frames of motion in
/// it, while 0.15s leaves 123. Long enough to read as a beat between screens, short enough
/// that a runner stalling for nine seconds does not cost nine seconds of anyone's attention.
let maxHold = 0.15

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

func makeGenerator(width: Int) -> AVAssetImageGenerator {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    // Height unconstrained, so the width is what decides the scale.
    generator.maximumSize = CGSize(width: width, height: 10_000)
    return generator
}

/// A grayscale reading of a frame, at half the output's own size.
///
/// The first version of this read 32x64 and was too coarse to see a progress ring turning
/// inside a 104-point circle on a 695-point screen: swept against real recordings it called two
/// thirds of the genuine motion static.
let digestWidth = max(targetWidth / 2, 32)
let digestHeight = digestWidth * 2

func digest(_ image: CGImage) -> [UInt8]? {
    var pixels = [UInt8](repeating: 0, count: digestWidth * digestHeight)
    guard let context = CGContext(
        data: &pixels,
        width: digestWidth,
        height: digestHeight,
        bitsPerComponent: 8,
        bytesPerRow: digestWidth,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: digestWidth, height: digestHeight))
    return pixels
}

func distance(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 255 }
    var total = 0
    for index in a.indices { total += abs(Int(a[index]) - Int(b[index])) }
    return Double(total) / Double(a.count)
}

// MARK: - Pass one: what moved, and when

let frameCount = max(Int(seconds * fps), 2)
let step = 1.0 / fps

let prober = makeGenerator(width: digestWidth)
var times: [Int] = []
var digests: [[UInt8]] = []
for index in 0..<frameCount {
    let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
    guard let image = try? prober.copyCGImage(at: time, actualTime: nil),
          let reading = digest(image) else { continue }
    times.append(index)
    digests.append(reading)
}

guard digests.count > 1 else {
    FileHandle.standardError.write(Data("only \(digests.count) frame(s) in \(input.lastPathComponent)\n".utf8))
    exit(1)
}

/// Which frames survive at a given bar for what counts as motion, and how long each is held.
func select(threshold: Double) -> [(index: Int, hold: Double)] {
    var kept: [(index: Int, hold: Double)] = []
    var last: [UInt8]?
    var pending = 0.0

    for (position, reading) in digests.enumerated() {
        if let last, distance(reading, last) < threshold {
            pending += step
            continue
        }
        if !kept.isEmpty {
            kept[kept.count - 1].hold = min(max(pending, step), maxHold)
        }
        kept.append((index: times[position], hold: step))
        last = reading
        pending = step
    }
    if !kept.isEmpty {
        kept[kept.count - 1].hold = min(max(pending, step), maxHold)
    }
    return kept
}

func fits(_ selection: [(index: Int, hold: Double)]) -> Bool {
    selection.count <= maxFrames && selection.reduce(0) { $0 + $1.hold } <= maxSeconds
}

// The bar starts at "anything at all moved" and rises until the result fits. Thirty steps of
// bisection over a range this wide settles to well under a hundredth of a level.
var low = 0.02
var high = 64.0
var chosen = select(threshold: low)
if !fits(chosen) {
    for _ in 0..<30 {
        let middle = (low + high) / 2
        let candidate = select(threshold: middle)
        if fits(candidate) {
            high = middle
            chosen = candidate
        } else {
            low = middle
        }
    }
    if !fits(chosen) { chosen = select(threshold: high) }
}

guard chosen.count > 1 else {
    FileHandle.standardError.write(Data("nothing moved in \(input.lastPathComponent)\n".utf8))
    exit(1)
}

// MARK: - Pass two: write only those frames, at full size

guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    UTType.gif.identifier as CFString,
    chosen.count,
    nil
) else {
    FileHandle.standardError.write(Data("cannot write \(output.path)\n".utf8))
    exit(1)
}

CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
] as CFDictionary)

let writer = makeGenerator(width: targetWidth)
var written = 0
for frame in chosen {
    let time = CMTime(seconds: Double(frame.index) / fps, preferredTimescale: 600)
    guard let image = try? writer.copyCGImage(at: time, actualTime: nil) else { continue }
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFUnclampedDelayTime: frame.hold,
            kCGImagePropertyGIFDelayTime: frame.hold
        ]
    ] as CFDictionary)
    written += 1
}

guard written > 1, CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("only \(written) frame(s) were written\n".utf8))
    exit(1)
}

let attributes = try? FileManager.default.attributesOfItem(atPath: output.path)
let bytes = (attributes?[.size] as? Int) ?? 0
let plays = chosen.reduce(0) { $0 + $1.hold }
print(
    "\(output.lastPathComponent): \(written) of \(digests.count) frames, "
    + "\(String(format: "%.1f", seconds))s recorded → \(String(format: "%.1f", plays))s, "
    + "\(bytes / 1024) KB"
)
