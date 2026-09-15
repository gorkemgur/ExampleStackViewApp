import Foundation

/// What the app says about itself before it asks for anything.
///
/// The order is not decorative. On a real phone the permission alert arrived at launch, fired
/// by a change-observer registration, before anybody had read a word about what the app does
/// or what it promises not to do — and the card written precisely to earn that permission was
/// still behind the dialog when the dialog was answered. Asking last, and only after the
/// promise has been made, is the whole point of this screen existing.
struct OnboardingPage: Identifiable, Equatable {

    enum Action: Equatable {
        /// Moves to the next page.
        case next
        /// Raises the system's photo permission alert, then finishes.
        case grantPhotos
        /// Finishes without asking for anything.
        case finish
    }

    let id: String
    let title: String
    /// The sentence that carries the page, set apart from the rest of the body.
    ///
    /// Not a second title and not a summary — it is one of the body's own sentences, lifted out
    /// and given weight. A five-line block of secondary grey has no entry point: nothing in it
    /// is more important than anything else, so a reader has to take all of it or none of it.
    /// Defaulted, and `var`, so the memberwise initialiser keeps working for anything that does
    /// not want one.
    var lead: String = ""
    let body: String
    let symbolName: String
    let action: Action
    let actionTitle: String
}

extension OnboardingPage {

    /// The four things somebody has to believe before handing over their photo library, in the
    /// order they have to believe them: what it looks for, that it is never taking the decision
    /// away from you, that nothing leaves the phone, and only then the ask.
    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: "what",
            title: "Four kinds of duplicate, not one",
            lead: "Identical copies that cost nothing to delete.",
            body: "Lower-quality re-sends of a photo you still have at full size. Leftovers from one press of the shutter. And shots that are merely alike — which stay your call, one by one.",
            symbolName: "square.stack.3d.down.right.fill",
            action: .next,
            actionTitle: "Next"
        ),
        OnboardingPage(
            id: "choose",
            title: "Nothing goes without you saying so",
            lead: "Only the rungs where deleting provably loses nothing arrive pre-ticked.",
            body: "Every deletion is confirmed twice, and photos land in Recently Deleted for thirty days. Files in a folder you share do not — the app says so on the screen where it matters.",
            symbolName: "checkmark.shield.fill",
            action: .next,
            actionTitle: "Next"
        ),
        OnboardingPage(
            id: "private",
            title: "Nothing leaves this phone",
            lead: "Every photo is opened, fingerprinted and compared here.",
            body: "Nothing is uploaded, nothing is sent anywhere, and originals kept in iCloud are left alone rather than pulled down over your connection.",
            symbolName: "lock.fill",
            action: .next,
            actionTitle: "Next"
        ),
        OnboardingPage(
            id: "access",
            title: "Now it needs to look",
            lead: "Duplicates only exist relative to the rest of the library, so a hand-picked selection cannot be checked — it needs the whole thing.",
            body: "You can add folders from Files later, and take any of it back in Settings whenever you like.",
            symbolName: "photo.stack.fill",
            action: .grantPhotos,
            actionTitle: "Allow photo access"
        )
    ]
}

/// Remembers whether this has been seen. Small, and exactly as durable as the app itself.
protocol OnboardingStoring: Sendable {
    var hasSeenOnboarding: Bool { get }
    func markSeen()
}

final class UserDefaultsOnboardingStore: OnboardingStoring, @unchecked Sendable {

    private static let key = "DupeSpace.hasSeenOnboarding"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasSeenOnboarding: Bool { defaults.bool(forKey: Self.key) }

    func markSeen() { defaults.set(true, forKey: Self.key) }
}

final class InMemoryOnboardingStore: OnboardingStoring, @unchecked Sendable {

    private let lock = NSLock()
    private var seen: Bool

    init(hasSeen: Bool = false) { seen = hasSeen }

    var hasSeenOnboarding: Bool {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    func markSeen() {
        lock.lock(); seen = true; lock.unlock()
    }
}

/// Drives the sequence, and owns the one rule that matters here: it is finished exactly once.
///
/// `markSeen()` used to be the sort of thing a view calls in `onDisappear`, which fires for
/// reasons that are not "the user got to the end" — a sheet being pushed over it, the app being
/// backgrounded on some iOS versions. A person who never reached the permission page would then
/// never be offered it again, and would be left with the wall and no way to understand it.
@MainActor
final class OnboardingViewModel: ObservableObject {

    @Published private(set) var index: Int = 0
    @Published private(set) var isComplete = false

    let pages: [OnboardingPage]
    private let store: any OnboardingStoring

    init(pages: [OnboardingPage] = OnboardingPage.all, store: any OnboardingStoring) {
        self.pages = pages
        self.store = store
    }

    var page: OnboardingPage { pages[min(index, pages.count - 1)] }
    var isLast: Bool { index >= pages.count - 1 }
    var progress: Double {
        guard pages.count > 1 else { return 1 }
        return Double(index) / Double(pages.count - 1)
    }

    func advance() {
        guard !isLast else { return }
        index += 1
    }

    func back() {
        guard index > 0 else { return }
        index -= 1
    }

    /// Skipping is allowed and does not skip the permission: the app still has its own card for
    /// that, and a wall somebody chose to walk into is not the same as one that ambushed them.
    func finish() {
        guard !isComplete else { return }
        isComplete = true
        store.markSeen()
    }
}

/// Who gets shown the screen.
///
/// Three inputs, and they do not collapse into one. `hasSeen` is the ordinary rule. `isUITesting`
/// has to veto it, because every UI test and the screenshot walk launch into what looks like a
/// fresh install — an onboarding screen in front of them stops all of them on the first frame,
/// and the failure would read as "the scan screen is missing" rather than as what it is.
///
/// `isForced` exists so that veto does not make this the one screen in the app nobody ever
/// photographs. It is the `-onboarding` flag, passed alongside `-ui-testing` and not instead of
/// it, exactly as `-clean-library` is — see `AppEnvironment`. It beats the store as well as the
/// veto, because the walk runs against whatever state the simulator is already in and cannot
/// assume a clean one.
enum OnboardingGate {

    static func shouldPresent(hasSeen: Bool, isUITesting: Bool, isForced: Bool) -> Bool {
        if isForced { return true }
        guard !isUITesting else { return false }
        return !hasSeen
    }
}
