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

    /// The card used to open at zero and say "nothing is selected by a plan of zero" directly
    /// above a bar reporting three selected items — the screen arguing with itself.
    func testTheBudgetOpensWhereTheAppsOwnSuggestionAlreadyIs() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())

        let preSelected = model.result.candidates
            .filter(\.isPreSelected)
            .reduce(Int64(0)) { $0 + $1.bytes }

        XCTAssertGreaterThan(model.budgetBytes, 0)
        XCTAssertEqual(Int64(model.budgetBytes), preSelected)
        XCTAssertFalse(model.budgetPlan.selected.isEmpty)
    }

    // MARK: - Overruling the engine

    private func exactGroupID(_ model: ReviewViewModel) -> String? {
        model.result.decisions.first { $0.relation == .exact }?.id
    }

    func testKeepingADifferentCopyMakesTheOldSurvivorDeletable() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard
            let groupID = exactGroupID(model),
            let decision = model.result.decisions.first(where: { $0.id == groupID }),
            let other = decision.allCandidates.first
        else { return XCTFail("fixture has no exact group to overrule") }

        let originalKeeper = decision.keeperID
        model.chooseKeeper(other, inGroup: groupID)

        XCTAssertEqual(model.keeperID(inGroup: groupID), other)
        XCTAssertTrue(
            model.liveCandidates.contains { $0.id == originalKeeper },
            "the copy the app wanted to keep is now the one on offer"
        )
        XCTAssertFalse(
            model.liveCandidates.contains { $0.id == other },
            "what the user keeps is never offered for deletion"
        )
        XCTAssertTrue(model.violations.isEmpty)
    }

    func testTheNewSurvivorIsNeverLeftTicked() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard
            let groupID = exactGroupID(model),
            let decision = model.result.decisions.first(where: { $0.id == groupID }),
            let other = decision.allCandidates.first
        else { return XCTFail("fixture has no exact group to overrule") }

        model.chooseKeeper(other, inGroup: groupID)

        XCTAssertFalse(model.selection.isSelected(other))
        XCTAssertTrue(model.violations.isEmpty, "a tick must never outlive the decision behind it")
    }

    func testChangingYourMindBackRestoresTheAppsChoice() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard
            let groupID = exactGroupID(model),
            let decision = model.result.decisions.first(where: { $0.id == groupID }),
            let other = decision.allCandidates.first
        else { return XCTFail("fixture has no exact group to overrule") }

        model.chooseKeeper(other, inGroup: groupID)
        model.chooseKeeper(decision.keeperID, inGroup: groupID)

        XCTAssertEqual(model.keeperID(inGroup: groupID), decision.keeperID)
        XCTAssertTrue(model.overrides.isEmpty)
    }

    /// The only thing in the app that may leave a group with nothing, and it takes an explicit
    /// per-group instruction to get there.
    func testDeletingAWholeGroupIsPossibleButOnlyWhenAskedFor() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard
            let groupID = exactGroupID(model),
            let decision = model.result.decisions.first(where: { $0.id == groupID })
        else { return XCTFail("fixture has no exact group") }

        let members = Set([decision.keeperID] + decision.allCandidates)

        model.setClearingEverything(true, inGroup: groupID)

        XCTAssertTrue(members.isSubset(of: model.selection.selectedIDs))
        XCTAssertTrue(model.violations.isEmpty, "the user named this group; the validator allows it")
        XCTAssertTrue(model.canDelete)
    }

    func testTakingItBackLeavesTheSurvivorAlone() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard
            let groupID = exactGroupID(model),
            let decision = model.result.decisions.first(where: { $0.id == groupID })
        else { return XCTFail("fixture has no exact group") }

        model.setClearingEverything(true, inGroup: groupID)
        model.setClearingEverything(false, inGroup: groupID)

        XCTAssertFalse(model.selection.isSelected(decision.keeperID))
        XCTAssertTrue(model.violations.isEmpty)
    }

    /// Nothing the app decides on its own may reach that state.
    func testNoAutomaticSelectionEverEmptiesAGroup() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())

        model.budgetBytes = Double(model.maxReclaimableBytes)
        model.budgetDepth = .similar
        model.applyBudgetPlan()
        XCTAssertTrue(model.violations.isEmpty, "a budget plan must never empty a group")

        for section in model.sections {
            model.setSelected(true, in: section)
        }
        XCTAssertTrue(model.violations.isEmpty, "selecting every offered copy must still be safe")
        XCTAssertTrue(model.clearedGroupIDs.isEmpty)
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

    func testDeletedCopiesStopBeingOffered() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        let before = model.sections.reduce(0) { $0 + $1.itemCount }
        let deleting = model.selection.count
        XCTAssertGreaterThan(deleting, 0)

        await model.delete()

        let after = model.sections.reduce(0) { $0 + $1.itemCount }
        XCTAssertEqual(after, before - deleting, "the list must stop offering copies that are gone")
        XCTAssertTrue(model.liveCandidates.allSatisfy { !model.deletedIDs.contains($0.id) })
        XCTAssertEqual(model.savings.totalBytes, 0, "nothing is selected right after a deletion")
    }

    func testADeletionLeavesAReceiptNamingWhatWasKept() async {
        let history = HistoryViewModel(store: InMemoryHistoryStore())
        await history.load()

        let scan = await makeResult()
        let model = ReviewViewModel(result: scan, deleter: StubDeleter(), history: history)
        let expected = model.selection.count

        await model.delete()

        XCTAssertEqual(history.log.deletions.count, 1)
        let receipt = history.log.deletions[0]
        XCTAssertEqual(receipt.itemCount, expected)
        XCTAssertTrue(
            receipt.items.allSatisfy { !$0.keptInsteadName.isEmpty },
            "every line of the receipt has to say what survived in its place"
        )
        XCTAssertEqual(receipt.judgementCallCount, 0, "the safe default deletes nothing risky")
        XCTAssertGreaterThan(receipt.reclaimedBytes, 0)
    }

    func testACancelledDeletionLeavesNoReceipt() async {
        let history = HistoryViewModel(store: InMemoryHistoryStore())
        await history.load()

        let model = ReviewViewModel(
            result: await makeResult(),
            deleter: StubDeleter(behaviour: .cancel),
            history: history
        )
        await model.delete()

        XCTAssertTrue(history.log.deletions.isEmpty, "nothing was deleted, so nothing is recorded")
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
