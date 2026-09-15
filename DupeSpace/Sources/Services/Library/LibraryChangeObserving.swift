import Foundation
import Photos

/// Tells the app when the photo library changed underneath it.
///
/// Without this, deleting a few photos in Photos and coming back here leaves the numbers
/// describing a library that no longer exists — and this app's whole claim is that its numbers
/// are honest.
protocol LibraryChangeObserving: Sendable {
    /// Starts watching. The handler runs on the main actor and may be called many times.
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

final class PhotoLibraryChangeObserver: NSObject, LibraryChangeObserving, PHPhotoLibraryChangeObserver, @unchecked Sendable {

    private let lock = NSLock()
    private var handler: (@MainActor () -> Void)?
    private var isRegistered = false

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        lock.lock()
        handler = onChange
        let needsRegistration = !isRegistered
        isRegistered = true
        lock.unlock()

        // Registering twice would deliver every change twice.
        if needsRegistration {
            PHPhotoLibrary.shared().register(self)
        }
    }

    func stopObserving() {
        lock.lock()
        handler = nil
        let wasRegistered = isRegistered
        isRegistered = false
        lock.unlock()

        if wasRegistered {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.lock()
        let handler = self.handler
        lock.unlock()

        guard let handler else { return }
        // PhotoKit calls this on a background queue; everything downstream is main-actor state.
        Task { @MainActor in handler() }
    }
}

/// For tests and previews: nothing changes unless a test says so.
final class StubLibraryChangeObserver: LibraryChangeObserving, @unchecked Sendable {

    private let lock = NSLock()
    private var handler: (@MainActor () -> Void)?

    var isObserving: Bool {
        lock.lock(); defer { lock.unlock() }
        return handler != nil
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        lock.lock(); handler = onChange; lock.unlock()
    }

    func stopObserving() {
        lock.lock(); handler = nil; lock.unlock()
    }

    /// Pretends the library changed.
    @MainActor
    func simulateChange() {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?()
    }
}
