import XCTest
@testable import DupeSpace

final class DeepLinkTests: XCTestCase {

    func testTheLinkTheWidgetPublishesIsTheLinkTheAppUnderstands() throws {
        // The widget builds its URL from this same type, so this is the round trip that a
        // hard-coded string on either side would have broken silently.
        let link = try XCTUnwrap(DeepLink(DeepLink.scan.url))
        XCTAssertEqual(link, .scan)
    }

    func testAnotherAppsSchemeIsNotOurs() {
        XCTAssertNil(DeepLink(URL(string: "https://example.com/scan")!))
        XCTAssertNil(DeepLink(URL(string: "dupespacex://scan")!))
    }

    func testAnUnknownDestinationIsRefusedRatherThanGuessedAt() {
        XCTAssertNil(DeepLink(URL(string: "dupespace://delete-everything")!))
        XCTAssertNil(DeepLink(URL(string: "dupespace://")!))
    }

    /// A link from an older build should still land somewhere sensible rather than nowhere.
    func testTrailingPathIsIgnored() {
        XCTAssertEqual(DeepLink(URL(string: "dupespace://scan/now?from=widget")!), .scan)
    }
}
