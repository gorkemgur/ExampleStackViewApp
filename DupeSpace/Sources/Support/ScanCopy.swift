import Foundation
import DupeCore

/// The words the app puts on each stage and tier.
///
/// Kept in one place because these strings are the product: a tier is only useful if its
/// label says what the user actually loses by acting on it.
enum ScanCopy {

    static func title(for stage: ScanProgress.Stage) -> String {
        switch stage {
        case .bucketing: return "Sorting by what we already know"
        case .hashing: return "Reading originals"
        case .fingerprinting: return "Fingerprinting photos"
        case .matching: return "Matching"
        case .planning: return "Working out what to keep"
        }
    }

    static func title(for tier: RegretTier) -> String {
        switch tier {
        case .identical: return "Identical copies"
        case .inferiorCopy: return "Lower-quality re-sends"
        case .burstLeftover: return "Burst leftovers"
        case .similar: return "Similar shots"
        }
    }

    static func subtitle(for tier: RegretTier) -> String {
        switch tier {
        case .identical:
            return "Byte for byte the same file. Deleting these loses nothing at all."
        case .inferiorCopy:
            return "Smaller re-encodes of a photo you still have at full size. Nothing is lost."
        case .burstLeftover:
            return "Other frames from one press of the shutter. Worth a look first."
        case .similar:
            return "Alike, but not the same photo. Your call, one by one."
        }
    }

    static func symbolName(for tier: RegretTier) -> String {
        switch tier {
        case .identical: return "doc.on.doc"
        case .inferiorCopy: return "arrow.down.right.circle"
        case .burstLeftover: return "square.stack.3d.down.right"
        case .similar: return "rectangle.on.rectangle.angled"
        }
    }
}
