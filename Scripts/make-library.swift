#!/usr/bin/env swift
//
// Build a real photo library on disk, with known duplicates in it.
//
//   swift Scripts/make-library.swift <output directory>
//
// Everything in this repository is tested against stubs. `PhotoKitMediaLibrary`,
// `PhotoKitAssetAnalyzer` and — the one that matters — `PhotoKitDeleter` have never been run,
// because a simulator starts with an empty Photos library and nothing was putting anything in
// it. `xcrun simctl addmedia` does, so the only thing missing was the media.
//
// The point is that the answer is known before the scan runs. Four kinds of relationship, laid
// out so a failure says which stage broke rather than just "fewer groups than expected":
//
//   * an exact pair   — the same bytes written twice. Settles at the digest stage.
//   * a re-send pair  — the same picture at half the size and a lower quality. No shared byte,
//                       no shared file size: only the perceptual hash can find it.
//   * a video pair    — the same frames re-encoded smaller. Only frame sampling can find it.
//   * singletons      — pictures and clips with no partner, which must produce no group at all.
//                       These are the half of the test that catches a matcher being too loose.
//
// Deterministic: every pixel comes from the seed, so the same library is built on every run and
// a failure reproduces.
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixture-library")
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

/// SplitMix64, so a scene is a function of its number and nothing else.
struct Seeded {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// A scene: a few soft blobs on a gradient. Enough low-frequency structure that a perceptual
/// hash has something to hold on to, and enough difference between scenes that two of them
/// are never within a matching distance of each other.
func draw(scene: Int, width: Int, height: Int) -> CGImage? {
    var random = Seeded(UInt64(scene) &* 0x9E37_79B9)
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    let base = (r: random.unit(), g: random.unit(), b: random.unit())
    context.setFillColor(red: base.r * 0.5, green: base.g * 0.5, blue: base.b * 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // A diagonal wash, so the hash sees a real gradient rather than a flat field.
    let wash = CGGradient(
        colorsSpace: CGColorSpaceDeviceRGB(),
        colors: [
            CGColor(red: base.r, green: base.g, blue: base.b, alpha: 1),
            CGColor(red: base.b * 0.3, green: base.r * 0.3, blue: base.g * 0.3, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )
    if let wash {
        context.drawLinearGradient(
            wash,
            start: .zero,
            end: CGPoint(x: width, y: height),
            options: []
        )
    }

    for _ in 0..<7 {
        let radius = Double(min(width, height)) * (0.08 + random.unit() * 0.22)
        let x = random.unit() * Double(width)
        let y = random.unit() * Double(height)
        context.setFillColor(
            red: random.unit(), green: random.unit(), blue: random.unit(), alpha: 0.55
        )
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    return context.makeImage()
}

func CGColorSpaceDeviceRGB() -> CGColorSpace { CGColorSpaceCreateDeviceRGB() }

@discardableResult
func writeJPEG(_ image: CGImage, to url: URL, quality: Double) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else { return false }
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: quality
    ] as CFDictionary)
    return CGImageDestinationFinalize(destination)
}

func scaled(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

/// A clip that pans across one scene, so consecutive frames differ and the sampler has
/// something to sample.
func writeVideo(scene: Int, to url: URL, width: Int, height: Int, seconds: Double, bitrate: Int) async throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate]
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
    )
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let fps = 15
    let frames = Int(seconds * Double(fps))
    // Twice the width, so panning across it never runs out of picture.
    guard let source = draw(scene: scene, width: width * 2, height: height) else { return }

    for index in 0..<frames {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        guard let pool = adaptor.pixelBufferPool else { break }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { break }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) {
            let offset = -Double(width) * Double(index) / Double(max(frames - 1, 1))
            context.draw(source, in: CGRect(x: offset, y: 0, width: Double(width) * 2, height: Double(height)))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
    }

    input.markAsFinished()
    await writer.finishWriting()
}

// MARK: - The library

var manifest: [String] = []

func note(_ line: String) {
    manifest.append(line)
    print(line)
}

// Photographs. Scenes 1-4 have partners; 5-8 do not.
for scene in 1...8 {
    guard let full = draw(scene: scene, width: 2400, height: 1800) else { continue }
    let original = directory.appendingPathComponent("photo-\(scene).jpg")
    writeJPEG(full, to: original, quality: 0.95)

    switch scene {
    case 1, 2:
        // The same bytes, under another name: an exact duplicate, found at the digest stage.
        let copy = directory.appendingPathComponent("photo-\(scene)-copy.jpg")
        try? FileManager.default.removeItem(at: copy)
        try? FileManager.default.copyItem(at: original, to: copy)
        note("exact    photo-\(scene).jpg = photo-\(scene)-copy.jpg")
    case 3, 4:
        // Half the size, a third of the quality: nothing in the metadata says these are the
        // same picture. Only the perceptual hash can say it.
        if let small = scaled(full, width: 1200, height: 900) {
            writeJPEG(small, to: directory.appendingPathComponent("photo-\(scene)-resend.jpg"), quality: 0.45)
            note("resend   photo-\(scene).jpg ≈ photo-\(scene)-resend.jpg")
        }
    default:
        note("single   photo-\(scene).jpg")
    }
}

// Clips. Scenes 11-13 have partners; 14-15 do not.
for scene in 11...15 {
    let original = directory.appendingPathComponent("clip-\(scene).mov")
    try await writeVideo(scene: scene, to: original, width: 640, height: 480, seconds: 3, bitrate: 2_500_000)

    if scene <= 13 {
        // The same footage, re-encoded smaller and at a fifth of the bitrate. Same duration,
        // same shape, no shared byte: this is the pair only frame sampling can settle.
        let resend = directory.appendingPathComponent("clip-\(scene)-resend.mov")
        try await writeVideo(scene: scene, to: resend, width: 480, height: 360, seconds: 3, bitrate: 500_000)
        note("resend   clip-\(scene).mov ≈ clip-\(scene)-resend.mov")
    } else {
        note("single   clip-\(scene).mov")
    }
}

let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
let photos = files.filter { $0.hasSuffix(".jpg") }.count
let videos = files.filter { $0.hasSuffix(".mov") }.count
note("")
note("\(photos) photos and \(videos) videos; 7 groups expected, 7 items on offer")

try? manifest.joined(separator: "\n").write(
    to: directory.appendingPathComponent("EXPECTED.txt"), atomically: true, encoding: .utf8
)
