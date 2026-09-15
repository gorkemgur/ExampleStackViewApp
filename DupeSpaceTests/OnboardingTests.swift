import XCTest
@testable import DupeSpace

/// Counts writes rather than recording the last one.
///
/// `InMemoryOnboardingStore` cannot tell "marked seen once" from "marked seen four times",
/// and the one rule `finish()` has is that it happens exactly once. A store that only
/// remembers the final value would pass that test no matter how many times it was written.
private final class CountingOnboardingStore: OnboardingStoring, @unchecked Sendable {

    private(set) var writes = 0
    private var seen: Bool

    init(hasSeen: Bool = false) { seen = hasSeen }

    var hasSeenOnboarding: Bool { seen }

    func markSeen() {
        writes += 1
        seen = true
    }
}

// MARK: - Who sees this screen

/// The gate is the whole reason the screen has a flag.
///
/// Three inputs decide it and they do not reduce to one: whether this person has seen it,
/// whether the app is being driven by a test, and whether something deliberately asked for it.
/// The middle one exists because every UI test and the screenshot walk launch with
/// `-ui-testing`, and an onboarding screen in front of them stops all of them on the first
/// frame. The third exists because suppressing it there would otherwise make this the one
/// screen in the app that is never photographed.
final class OnboardingGateTests: XCTestCase {

    func testFirstLaunchPresentsOnboarding() {
        XCTAssertTrue(OnboardingGate.shouldPresent(hasSeen: false, isUITesting: false, isForced: false))
    }

    func testAlreadySeenDoesNotPresentAgain() {
        XCTAssertFalse(OnboardingGate.shouldPresent(hasSeen: true, isUITesting: false, isForced: false))
    }

    func testUITestingSuppressesOnboarding() {
        XCTAssertFalse(
            OnboardingGate.shouldPresent(hasSeen: false, isUITesting: true, isForced: false),
            "a UI test launches into a fresh install; onboarding in front of it stops every test in the bundle"
        )
    }

    func testForcingItShowsItUnderUITesting() {
        XCTAssertTrue(
            OnboardingGate.shouldPresent(hasSeen: false, isUITesting: true, isForced: true),
            "the screenshot walk has to be able to reach the one screen -ui-testing otherwise hides"
        )
    }

    func testForcingItBeatsAStoreThatSaysSeen() {
        XCTAssertTrue(
            OnboardingGate.shouldPresent(hasSeen: true, isUITesting: true, isForced: true),
            "the walk runs against whatever state the simulator is already in"
        )
    }
}

// MARK: - The sequence

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    private func makeModel(store: any OnboardingStoring = InMemoryOnboardingStore()) -> OnboardingViewModel {
        OnboardingViewModel(store: store)
    }

    func testStartsOnTheFirstPage() {
        let model = makeModel()

        XCTAssertEqual(model.index, 0)
        XCTAssertEqual(model.page.id, OnboardingPage.all.first?.id)
        XCTAssertFalse(model.isComplete)
    }

    func testAdvanceStopsOnTheLastPage() {
        let model = makeModel()

        for _ in 0..<(OnboardingPage.all.count * 2) {
            model.advance()
        }

        XCTAssertEqual(model.index, OnboardingPage.all.count - 1)
        XCTAssertTrue(model.isLast)
    }

    func testBackStopsOnTheFirstPage() {
        let model = makeModel()
        model.advance()
        model.back()
        model.back()

        XCTAssertEqual(model.index, 0)
    }

    func testProgressRunsFromZeroToOne() {
        let model = makeModel()
        XCTAssertEqual(model.progress, 0, accuracy: 0.0001)

        while !model.isLast { model.advance() }

        XCTAssertEqual(model.progress, 1, accuracy: 0.0001)
    }

    /// The rule the file was rewritten for: see the note on `finish()`.
    func testFinishIsRecordedExactlyOnce() {
        let store = CountingOnboardingStore()
        let model = OnboardingViewModel(store: store)

        model.finish()
        model.finish()
        model.finish()

        XCTAssertEqual(store.writes, 1)
        XCTAssertTrue(model.isComplete)
    }

    func testFinishMarksTheStoreSeen() {
        let store = InMemoryOnboardingStore()
        let model = OnboardingViewModel(store: store)

        XCTAssertFalse(store.hasSeenOnboarding)
        model.finish()

        XCTAssertTrue(store.hasSeenOnboarding)
    }

    /// Ordering is a contract here, not a layout preference.
    ///
    /// The screen exists because the permission alert used to arrive at launch, ahead of the
    /// card written to earn it. A page order that puts the ask anywhere but last puts this app
    /// back where it started, and nothing else in the codebase would notice.
    func testThePermissionIsAskedForOnTheLastPageAndNowhereElse() {
        let pages = OnboardingPage.all

        XCTAssertEqual(pages.last?.action, .grantPhotos)
        XCTAssertEqual(
            pages.filter { $0.action == .grantPhotos }.count,
            1,
            "one ask, at the end"
        )
        XCTAssertTrue(
            pages.dropLast().allSatisfy { $0.action == .next },
            "nothing before the last page may ask for anything"
        )
    }

    func testEveryPageCarriesItsOwnCopyAndControl() {
        for page in OnboardingPage.all {
            XCTAssertFalse(page.title.isEmpty, "\(page.id) has no title")
            XCTAssertFalse(page.body.isEmpty, "\(page.id) has no body")
            XCTAssertFalse(page.actionTitle.isEmpty, "\(page.id) has no button")
            XCTAssertFalse(page.symbolName.isEmpty, "\(page.id) has no symbol")
        }
    }
}
