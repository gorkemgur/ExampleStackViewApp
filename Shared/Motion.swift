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

    /// A reading that updates continuously while work runs.
    ///
    /// The third kind of movement, and the one that was being drawn with the first. A spring
    /// has overshoot and a settle; give it a new value several times a second and it never
    /// reaches either, so a scan progress bar animated with `content` spent the whole scan
    /// wobbling behind the number it was meant to be showing. Linear and short: the bar is
    /// simply where the work is.
    static let readout: Animation = .linear(duration: 0.15)
}
