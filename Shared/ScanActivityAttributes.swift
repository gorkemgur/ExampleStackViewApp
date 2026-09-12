import ActivityKit
import Foundation
import DupeCore

/// The contract between the app and the Live Activity.
///
/// Compiled into both, so neither can drift from the other: adding a field the widget does not
/// know about is a build error rather than a blank space on someone's Lock Screen.
struct ScanActivityAttributes: ActivityAttributes {

    /// Everything that moves while the scan runs.
    struct ContentState: Codable, Hashable {
        var scan: LiveScanState
    }

    /// Fixed for the life of the activity: how big the library was when the scan started.
    var libraryItemCount: Int

    init(libraryItemCount: Int) {
        self.libraryItemCount = max(libraryItemCount, 0)
    }
}

extension ScanActivityAttributes.ContentState {

    init(_ scan: LiveScanState) {
        self.init(scan: scan)
    }
}
