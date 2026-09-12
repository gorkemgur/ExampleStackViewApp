import SwiftUI

/// Two curves, used everywhere.
///
/// The app had nine slightly different durations for the same class of change, which nobody
/// chose on purpose and which makes the same gesture feel different on adjacent screens. There
/// are only two kinds of movement here: something on screen changing, and a control answering a
/// touch. One curve each.
enum Motion {

    /// Content appearing, changing or being replaced.
    static let content: Animation = .snappy(duration: 0.32)

    /// A control acknowledging a touch, or a value ticking over. Shorter, because the user is
    /// waiting on it.
    static let control: Animation = .snappy(duration: 0.22)
}
