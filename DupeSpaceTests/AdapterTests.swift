import AVFoundation
import CoreGraphics
import XCTest
import DupeCore
@testable import DupeSpace

/// The adapters between the engine and the operating system, which had no tests at all.
///
/// `DupeCore` is tested to within an inch of its life and every one of those tests hands it
/// hashes and byte counts that I wrote by hand. The code that turns a real picture into those
/// numbers, a real video into a signature, and a real original into a file on disk was
/// measured by nothing. Three of them can be exercised on a simulator without a photo library,
/// and this is those three; `PhotoKitMediaLibrary`, `PhotoKitAssetAnalyzer` and
/// `PhotoKitDeleter` need a library, which is what the `real` CI job is for.
final class AdapterTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    // MARK: - GrayImageRenderer

    /// Half black, half white, split down the middle.
    private func halves(width: Int, height: Int, leftIsDark: Bool) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(gray: leftIsDark ? 0 : 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(gray: leftIsDark ? 1 : 0, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func mean(_ image: GrayImage, x: Range<Int>, y: Range<Int>) -> Double {
        var total = 0
        var count = 0
        for row in y {
            for column in x {
                total += Int(image.pixels[row * image.width + column])
                count += 1
            }
        }
        return count > 0 ? Double(total) / Double(count) : 0
    }

    func testTheRenderedBufferIsTheSizeItWasAskedFor() throws {
        let rendered = try XCTUnwrap(GrayImageRenderer.render(halves(width: 200, height: 120, leftIsDark: true)))
        XCTAssertEqual(rendered.width, GrayImageRenderer.renderSize)
        XCTAssertEqual(rendered.height, GrayImageRenderer.renderSize)
        XCTAssertEqual(rendered.pixels.count, GrayImageRenderer.renderSize * GrayImageRenderer.renderSize)
    }

    /// The one that would have caught a silent mirror.
    ///
    /// `CGContext` draws with the origin at the *bottom* left and `GrayImage` indexes from the
    /// top, so a renderer can be flipped and still produce perfectly stable, perfectly wrong
    /// fingerprints — stable enough that every hashing test in `DupeCore` would keep passing,
    /// because both sides of every comparison there are flipped identically.
    func testTheLeftOfThePictureIsTheLeftOfTheBuffer() throws {
        let rendered = try XCTUnwrap(GrayImageRenderer.render(halves(width: 200, height: 200, leftIsDark: true)))
        let size = rendered.width
        let left = mean(rendered, x: 0..<(size / 2 - 4), y: 0..<size)
        let right = mean(rendered, x: (size / 2 + 4)..<size, y: 0..<size)

        XCTAssertLessThan(left, 40, "the dark half of the picture came out at \(left)")
        XCTAssertGreaterThan(right, 215, "the bright half of the picture came out at \(right)")
    }

    func testMirroringThePictureMirrorsTheBuffer() throws {
        let normal = try XCTUnwrap(GrayImageRenderer.render(halves(width: 160, height: 160, leftIsDark: true)))
        let mirrored = try XCTUnwrap(GrayImageRenderer.render(halves(width: 160, height: 160, leftIsDark: false)))
        let size = normal.width

        XCTAssertLessThan(mean(normal, x: 0..<(size / 2 - 4), y: 0..<size), 40)
        XCTAssertGreaterThan(mean(mirrored, x: 0..<(size / 2 - 4), y: 0..<size), 215)
    }

    func testAZeroSizeRenderIsRefusedRatherThanCrashing() throws {
        XCTAssertNil(GrayImageRenderer.render(try halves(width: 40, height: 40, leftIsDark: true), size: 0))
    }

    /// Two pictures of different shapes, stretched into the same square, must not become the
    /// same fingerprint. The square is deliberate — copies of one photo share an aspect ratio
    /// — but it must not flatten genuinely different pictures into each other.
    func testTwoDifferentPicturesDoNotRenderToTheSameFingerprint() throws {
        let a = try XCTUnwrap(GrayImageRenderer.render(halves(width: 200, height: 100, leftIsDark: true)))
        let b = try XCTUnwrap(GrayImageRenderer.render(halves(width: 200, height: 100, leftIsDark: false)))
        XCTAssertNotEqual(PerceptualHasher.dHash(a), PerceptualHasher.dHash(b))
    }

    // MARK: - VideoFrameSampler

    /// A clip that pans across a generated scene, so consecutive frames genuinely differ.
    @discardableResult
    private func writeClip(
        named name: String,
        seed: Int,
        width: Int = 320,
        height: Int = 240,
        seconds: Double = 4,
        bitrate: Int = 1_200_000
    ) async throws -> URL {
        let url = root.appendingPathComponent(name)
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
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) {
                let progress = Double(index) / Double(max(frames - 1, 1))
                context.setFillColor(gray: 0.1, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                // Three bars sweeping at different rates: every sample position sees a
                // different arrangement, which is what a signature needs to carry evidence.
                for bar in 0..<3 {
                    let phase = (progress + Double(bar) / 3 + Double(seed) / 7).truncatingRemainder(dividingBy: 1)
                    context.setFillColor(
                        red: Double((seed + bar) % 3) / 2,
                        green: Double((seed + bar * 2) % 3) / 2,
                        blue: 1 - Double(bar) / 3,
                        alpha: 1
                    )
                    context.fill(CGRect(
                        x: phase * Double(width) - Double(width) / 6,
                        y: Double(bar) * Double(height) / 3,
                        width: Double(width) / 3,
                        height: Double(height) / 3
                    ))
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
        }

        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    func testAClipProducesAFullSignature() async throws {
        let url = try await writeClip(named: "one.mov", seed: 1)
        let signature = await VideoFrameSampler.signature(for: AVURLAsset(url: url))
        let unwrapped = try XCTUnwrap(signature, "a four-second clip produced no signature at all")

        XCTAssertEqual(unwrapped.frameHashes.count, VideoSignature.samplePositions.count)
        XCTAssertTrue(unwrapped.carriesEnoughEvidence)
    }

    /// The pair the whole video half of this app exists for: the same footage re-encoded
    /// smaller and at a fraction of the bitrate. No shared byte, no shared file size.
    func testTheSameFootageReEncodedStillMatchesItself() async throws {
        let original = try await writeClip(named: "trip.mov", seed: 4, width: 480, height: 360, bitrate: 2_000_000)
        let resend = try await writeClip(named: "trip-resend.mov", seed: 4, width: 320, height: 240, bitrate: 400_000)

        // Awaited into a local before unwrapping: `XCTUnwrap` takes an autoclosure, and an
        // autoclosure cannot carry an `await`.
        let first = await VideoFrameSampler.signature(for: AVURLAsset(url: original))
        let second = await VideoFrameSampler.signature(for: AVURLAsset(url: resend))
        let a = try XCTUnwrap(first, "the original produced no signature")
        let b = try XCTUnwrap(second, "the re-encode produced no signature")

        let comparison = try XCTUnwrap(
            VideoMatcher.compare(a, b),
            "two full signatures did not even overlap enough to be compared"
        )
        XCTAssertLessThan(
            comparison.averageDistance, 8,
            "the same footage at a fifth of the bitrate averaged \(comparison.averageDistance) apart"
        )
    }

    /// And the direction that matters more: two clips of the same length and shape that are
    /// *not* the same footage must not be called the same footage.
    func testTwoDifferentClipsOfTheSameLengthDoNotMatch() async throws {
        let one = try await writeClip(named: "a.mov", seed: 2)
        let other = try await writeClip(named: "b.mov", seed: 5)

        let first = await VideoFrameSampler.signature(for: AVURLAsset(url: one))
        let second = await VideoFrameSampler.signature(for: AVURLAsset(url: other))
        let a = try XCTUnwrap(first, "the first clip produced no signature")
        let b = try XCTUnwrap(second, "the second clip produced no signature")

        let comparison = try XCTUnwrap(VideoMatcher.compare(a, b))
        XCTAssertGreaterThan(
            comparison.averageDistance, 8,
            "two unrelated clips averaged only \(comparison.averageDistance) apart"
        )
    }

    func testAFileThatIsNotAVideoProducesNoSignature() async throws {
        let url = root.appendingPathComponent("not-a-video.mov")
        try Data("this is not a movie".utf8).write(to: url)
        let signature = await VideoFrameSampler.signature(for: AVURLAsset(url: url))
        XCTAssertNil(signature)
    }


    // MARK: - FileSystemOriginalExporter

    /// The promise the concept document has made since day one: before anything is destroyed,
    /// the original bytes can be written to a folder the user picks, with a manifest beside
    /// them saying what each file was and which copy it was being deleted in favour of.
    ///
    /// It had no tests. The photo-library half needs a library and belongs to the `real` job;
    /// the folder half runs anywhere, and it is the half where a deletion cannot be undone.

    private func grant(_ url: URL) throws -> (GrantedFolder, InMemoryFolderRegistry) {
        let folder = try XCTUnwrap(FolderAccess.makeGrant(for: url), "could not bookmark \(url.lastPathComponent)")
        return (folder, InMemoryFolderRegistry(folders: [folder]))
    }

    private func fileItem(_ name: String, in folder: GrantedFolder, bytes: Int64) -> MediaItem {
        MediaItem(
            id: FileItemID.make(folderID: folder.id, relativePath: name),
            source: .fileFolder,
            kind: .document,
            displayName: name,
            byteSize: bytes
        )
    }

    private func entry(for item: MediaItem, as fileName: String, kept: String = "keeper") -> ExportManifest.Entry {
        ExportManifest.Entry(
            itemID: item.id,
            displayName: item.displayName,
            exportedFileName: fileName,
            byteSize: item.byteSize,
            kind: "file",
            source: "folder",
            groupID: "group-1",
            cost: "Costs nothing",
            keptItemID: kept,
            keptDisplayName: "the one that stayed",
            creationDate: nil
        )
    }

    func testTheOriginalsAndTheManifestBothLand() async throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("the original bytes".utf8).write(to: source.appendingPathComponent("a.txt"))

        let (folder, registry) = try grant(source)
        let item = fileItem("a.txt", in: folder, bytes: 18)
        let receipt = try await FileSystemOriginalExporter(registry: registry)
            .export([(item: item, entry: entry(for: item, as: "001-a.txt"))], to: destination)

        XCTAssertTrue(receipt.isComplete)
        XCTAssertEqual(receipt.exportedIDs, [item.id])

        let exportRoot = destination.appendingPathComponent(receipt.folderName, isDirectory: true)
        let written = exportRoot.appendingPathComponent("originals/001-a.txt")
        XCTAssertEqual(try Data(contentsOf: written), Data("the original bytes".utf8),
                       "the export has to be the bytes, not a rendition of them")

        // `.iso8601`, because that is what `encoded()` writes. A plain decoder reads the
        // entries fine and then fails on `createdAt`, which would have made this test look
        // like a manifest bug rather than a decoder one.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            ExportManifest.self,
            from: try Data(contentsOf: exportRoot.appendingPathComponent("manifest.json"))
        )
        XCTAssertEqual(manifest.entries.count, 1)
        XCTAssertEqual(manifest.entries.first?.exportedFileName, "001-a.txt")
        XCTAssertEqual(manifest.entries.first?.keptItemID, "keeper",
                       "the column that turns 'I deleted the wrong one' into 'here is the one I meant to keep'")
    }

    /// The failure this feature would be worse than useless without: nothing could be written,
    /// so nothing is claimed, and the folder it made is taken away again.
    func testNothingWritableMeansNothingExportedAndNoFolderLeftBehind() async throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let (folder, registry) = try grant(source)
        // Granted, indexed, and then gone — a file that moved between the scan and the export.
        let missing = fileItem("gone.txt", in: folder, bytes: 10)

        do {
            _ = try await FileSystemOriginalExporter(registry: registry)
                .export([(item: missing, entry: entry(for: missing, as: "001-gone.txt"))], to: destination)
            XCTFail("an export that wrote nothing reported success")
        } catch let error as ExportError {
            XCTAssertEqual(error, .nothingExported)
        }

        let left = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertTrue(left.isEmpty, "an empty export folder was left behind: \(left)")
    }

    /// Two exports into the same place inside the same second.
    ///
    /// The folder name goes down to the second and the root is made with
    /// `withIntermediateDirectories: false` on purpose, because the alternative was worse than
    /// an error: a silent merge found every target filename already taken, refused every write,
    /// concluded nothing had been exported — and then deleted the directory holding the *first*
    /// export's originals and manifest.
    func testASecondExportIntoTheSameFolderIsRefusedRatherThanMerged() async throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: source.appendingPathComponent("a.txt"))

        let (folder, registry) = try grant(source)
        let item = fileItem("a.txt", in: folder, bytes: 7)
        let exporter = FileSystemOriginalExporter(registry: registry)
        let plan = [(item: item, entry: entry(for: item, as: "001-a.txt"))]

        let first = try await exporter.export(plan, to: destination)
        let firstRoot = destination.appendingPathComponent(first.folderName, isDirectory: true)

        // Only meaningful if the two land in the same second; if the clock rolled over, the
        // second export legitimately gets its own folder and there is nothing to protect.
        do {
            let second = try await exporter.export(plan, to: destination)
            XCTAssertNotEqual(second.folderName, first.folderName,
                              "two exports shared a folder name and neither was refused")
        } catch let error as ExportError {
            guard case .couldNotCreateFolder = error else {
                return XCTFail("refused for the wrong reason: \(error)")
            }
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: firstRoot.appendingPathComponent("manifest.json").path),
            "the first export's manifest was destroyed by the second"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: firstRoot.appendingPathComponent("originals/001-a.txt").path),
            "the first export's originals were destroyed by the second"
        )
    }

    /// Sortable and readable a year later, and — the part that matters — unique per second.
    func testTheFolderNameGoesDownToTheSecond() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let name = FileSystemOriginalExporter.folderName(at: base)
        let aSecondLater = FileSystemOriginalExporter.folderName(at: base.addingTimeInterval(1))

        XCTAssertNotEqual(name, aSecondLater, "two exports a second apart would collide")
        XCTAssertTrue(name.hasPrefix("DupeSpace Export "), name)
    }
}
