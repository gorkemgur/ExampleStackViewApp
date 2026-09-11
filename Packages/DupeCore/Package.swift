// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DupeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DupeCore", targets: ["DupeCore"])
    ],
    targets: [
        .target(
            name: "DupeCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "DupeCoreTests", dependencies: ["DupeCore"])
    ]
)
