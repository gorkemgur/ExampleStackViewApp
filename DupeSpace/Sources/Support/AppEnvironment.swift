import Foundation
import DupeCore

/// Picks the real services or the deterministic fixtures.
enum AppEnvironment {

    /// Set by the UI test bundle. Keeps the permission alert — which nothing can tap on a CI
    /// machine — out of the way, and pins the library to a known fixture.
    static let uiTestingFlag = "-ui-testing"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingFlag)
    }

    static func makeLibrary() -> MediaLibrary {
        isUITesting ? StubMediaLibrary.uiTestFixture() : PhotoKitMediaLibrary()
    }

    static func makeAnalyzer() -> any AssetAnalyzing {
        isUITesting ? StubAssetAnalyzer.uiTestFixture() : PhotoKitAssetAnalyzer()
    }
}
