import Foundation
import DupeCore

/// How much of the photo library this app is allowed to see.
enum LibraryAccess: Equatable, Sendable {
    case notDetermined
    /// The user picked individual photos. Useless for finding duplicates across a library,
    /// and the UI says so rather than pretending to scan.
    case limited
    case denied
    case restricted
    case authorized
}

/// Everything the app needs from a photo library, behind a protocol so the UI can be driven
/// by a deterministic fixture in tests instead of whatever happens to be on the simulator.
protocol MediaLibrary: Sendable {
    func currentAccess() -> LibraryAccess
    func requestAccess() async -> LibraryAccess
    /// Metadata for every asset. Does not read pixel data or download anything from iCloud.
    func loadInventory() async throws -> [MediaItem]
}
