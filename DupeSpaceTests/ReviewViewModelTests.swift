import XCTest
import DupeCore
@testable import DupeSpace

@MainActor
final class ReviewViewModelTests: XCTestCase {

    private func makeResult() async -> ScanResult {
        let scan = ScanViewModel(analyzer: StubAssetAnalyzer.uiTestFixture())
        scan.start(items: StubMediaLibrary.sampleItems())
        let deadline = Date().addingTimeInterval(10)
        while scan.isScanning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return scan.result ?? .empty
    }

    func testOpensWithOnlyTheLosslessCopiesTicked() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())

        XCTAssertFalse(model.selection.isEmpty)
        XCTAssertEqual(model.judgementCallCount, 0, "nothing risky may be ticked before the user acts")
        XCTAssertTrue(model.deepestSelectedTier?.isLossless ?? true)
        XCTAssertTrue(model.violations.isEmpty)
    }

    func testSectionsAreOrderedByWhatDeletingCosts() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        let tiers = model.sections.map(\.tier)
        XCTAssertEqual(tiers, tiers.sorted(), "cheapest tier has to come first")
        XCTAssertEqual(tiers.first, .identical)
    }

    func testSavingsFollowTheSelection() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        let before = model.savings.totalBytes

        guard let extra = model.result.candidates.first(where: { !$0.isPreSelected }) else {
            return XCTFail("fixture has no manual-review candidate")
        }
        model.toggle(extra.id)
        XCTAssertEqual(model.savings.totalBytes, before + extra.bytes)
    }

    func testBudgetPlanStaysInsideTheChosenDepth() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        model.budgetBytes = Double(model.maxReclaimableBytes)

        model.budgetDepth = .inferiorCopy
        XCTAssertTrue(
            model.budgetPlan.selected.allSatisfy { $0.tier.isLossless },
            "the no-loss setting must never reach a judgement call"
        )

        let losslessOnly = model.budgetPlan.reclaimedBytes

        model.budgetDepth = .similar
        XCTAssertGreaterThanOrEqual(
            model.budgetPlan.reclaimedBytes,
            losslessOnly,
            "allowing more tiers cannot reclaim less"
        )
    }

    func testApplyingABudgetPlanReplacesTheSelection() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        model.budgetBytes = 1
        model.budgetDepth = .inferiorCopy
        model.applyBudgetPlan()

        XCTAssertEqual(model.selection.selectedIDs, model.budgetPlan.selectedIDs)
        XCTAssertTrue(model.violations.isEmpty)
    }

    func testResetReturnsToTheSafeDefault() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard let riskiest = model.sections.last, !riskiest.tier.isLossless else {
            return XCTFail("fixture produced no judgement-call tier")
        }
        model.setSelected(true, in: riskiest)
        XCTAssertGreaterThan(model.judgementCallCount, 0)

        model.resetToSafeDefaults()
        XCTAssertEqual(model.judgementCallCount, 0)
    }

    // MARK: - Deletion

    func testDeletingSendsExactlyTheSelectedIdentifiers() async {
        let deleter = StubDeleter()
        let model = ReviewViewModel(result: await makeResult(), deleter: deleter)
        let expected = model.selection.selectedIDs.sorted()

        await model.delete()

        XCTAssertEqual(deleter.received, [expected])
        XCTAssertEqual(model.outcome?.deletedIDs, expected)
        XCTAssertTrue(model.selection.isEmpty, "a completed deletion must not leave stale ticks behind")
        XCTAssertNil(model.failure)
    }

    /// The button is disabled in this state, but the guard cannot live in the UI: this is the
    /// call that destroys files.
    func testASelectionContainingAKeeperIsRefusedBeforeAnythingIsSent() async {
        let deleter = StubDeleter()
        let model = ReviewViewModel(result: await makeResult(), deleter: deleter)

        guard let keeperID = model.result.decisions.first?.keeperID else {
            return XCTFail("fixture produced no groups")
        }
        model.toggle(keeperID)

        XCTAssertFalse(model.canDelete)
        await model.delete()

        XCTAssertTrue(deleter.received.isEmpty, "nothing may reach the library from an invalid selection")
        XCTAssertNil(model.outcome)
    }

    func testEmptySelectionDeletesNothing() async {
        let deleter = StubDeleter()
        let model = ReviewViewModel(result: await makeResult(), deleter: deleter)
        for section in model.sections {
            model.setSelected(false, in: section)
        }

        XCTAssertFalse(model.canDelete)
        await model.delete()
        XCTAssertTrue(deleter.received.isEmpty)
    }

    func testCancellingAtTheSystemPromptKeepsTheSelection() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter(behaviour: .cancel))
        let before = model.selection.selectedIDs

        await model.delete()

        XCTAssertNil(model.outcome)
        XCTAssertEqual(model.selection.selectedIDs, before, "a cancelled deletion must not discard the user's work")
        XCTAssertNotNil(model.failure)
    }

    func testAFailedDeletionIsReported() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter(behaviour: .fail("disk on fire")))
        await model.delete()

        XCTAssertNil(model.outcome)
        XCTAssertEqual(model.failure, "disk on fire")
        XCTAssertFalse(model.isDeleting)
    }
}
