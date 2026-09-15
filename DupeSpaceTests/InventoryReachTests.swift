import XCTest
import Photos
import DupeCore
@testable import DupeSpace

/// What the inventory pass is able to see at all.
///
/// Nothing here touches a photo library. `PHFetchOptions` is a value the app builds and hands
/// to PhotoKit, so it can be read back directly, and each assertion pins a decision that is
/// otherwise invisible until somebody scans a real library and notices an absence they cannot
/// name.
final class InventoryReachTests: XCTestCase {

    func testEveryFrameOfABurstIsInTheInventory() {
        let options = PhotoKitMediaLibrary.inventoryFetchOptions()

        XCTAssertTrue(
            options.includeAllBurstAssets,
            """
            PHFetchOptions defaults this to false, so a fetch returns only the one frame Photos \
            chose as the burst's representative. Burst leftovers are a whole rung of this app's \
            ladder; with the default left alone that rung can never hold anything, and the app \
            reports an empty result that is indistinguishable from a clean library.
            """
        )
    }

    func testHiddenAssetsStayOutOfTheInventory() {
        let options = PhotoKitMediaLibrary.inventoryFetchOptions()

        XCTAssertFalse(
            options.includeHiddenAssets,
            "Photos hides these behind a Face ID prompt; an app that lists them in a grid undoes that"
        )
    }

    func testTheInventoryIsNewestFirst() {
        let options = PhotoKitMediaLibrary.inventoryFetchOptions()

        XCTAssertEqual(options.sortDescriptors?.count, 1)
        XCTAssertEqual(options.sortDescriptors?.first?.key, "creationDate")
        XCTAssertEqual(options.sortDescriptors?.first?.ascending, false)
    }
}
