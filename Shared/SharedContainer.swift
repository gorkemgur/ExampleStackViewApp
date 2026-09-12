import Foundation
import DupeCore

/// The App Group both halves of the app agree on.
///
/// A widget runs in its own process with no photo library access, so everything it shows was
/// left in this container by the app. Compiled into both targets so there is one spelling of
/// the identifier rather than two that can drift apart.
enum SharedContainer {

    static let appGroupID = "group.com.gorkemgur.dupespace"

    /// `nil` when the App Group is not available — an unsigned build, or an entitlement that
    /// was never granted. Callers show a placeholder rather than inventing numbers.
    static func snapshotStore() -> WidgetSnapshotStore? {
        WidgetSnapshotStore(appGroupID: appGroupID)
    }
}
