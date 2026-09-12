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

    // MARK: - Keeping a copy before deleting

    func testExportingWritesEverySelectedCopy() async {
        let model = ReviewViewModel(
            result: await makeResult(),
            deleter: StubDeleter(),
            exporter: StubOriginalExporter()
        )

        await model.exportOriginals(to: URL(fileURLWithPath: "/tmp"))

        let receipt = model.exportReceipt
        XCTAssertNotNil(receipt)
        XCTAssertEqual(Set(receipt?.exportedIDs ?? []), model.selection.selectedIDs)
        XCTAssertTrue(model.exportCoversSelection)
    }

    /// A green tick above a red key, covering a selection it no longer describes, is the one
    /// way this feature could make someone *less* safe than not having it.
    func testTickingSomethingAfterAnExportInvalidatesIt() async {
        let model = ReviewViewModel(
            result: await makeResult(),
            deleter: StubDeleter(),
            exporter: StubOriginalExporter()
        )
        await model.exportOriginals(to: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(model.exportCoversSelection)

        guard let extra = model.liveCandidates.first(where: { !model.selection.isSelected($0.id) }) else {
            return XCTFail("fixture has nothing left to add to the selection")
        }
        model.toggle(extra.id)

        XCTAssertFalse(model.exportCoversSelection, "the receipt no longer covers what is ticked")
    }

    /// Every row of the manifest has to name the copy that stays — that column is the whole
    /// reason the export makes a wrong decision recoverable.
    func testTheExportPlanNamesWhatStaysForEveryCopy() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())

        let plan = model.exportPlan
        XCTAssertFalse(plan.isEmpty)
        for step in plan {
            XCTAssertFalse(step.entry.keptItemID.isEmpty)
            XCTAssertNotEqual(step.entry.keptItemID, step.entry.itemID, "a copy cannot be kept in its own place")
            XCTAssertFalse(step.entry.exportedFileName.isEmpty)
        }
        XCTAssertEqual(
            Set(plan.map(\.entry.exportedFileName)).count,
            plan.count,
            "two originals may never be written to one filename"
        )
    }

    // MARK: - The filter is a scope, not just a way of looking

    /// The worst thing a screen like this can do is select something the person cannot see.
    ///
    /// The plan used to be built from every live candidate regardless of the filter. Filter to
    /// Videos, drag the fader to the end, tap the key — and the dock reported a selection full
    /// of photo groups that the list was not showing, on the one screen in the app where the
    /// next tap deletes things.
    func testAPlanNeverTicksSomethingTheFilterIsHiding() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard model.availableKinds.count > 1 else {
            return XCTFail("fixture needs more than one kind for this to mean anything")
        }

        model.kindFilter = .video
        model.budgetDepth = .similar
        model.budgetBytes = Double(model.plannableBytes)
        model.applyBudgetPlan()

        let onScreen = Set(model.visibleSections.flatMap(\.candidateIDs))
        XCTAssertFalse(model.selection.isEmpty, "a full-reach plan on a kind that has copies must select something")
        XCTAssertTrue(
            model.selection.selectedIDs.allSatisfy(onScreen.contains),
            "the plan ticked a copy the list was not showing"
        )
    }

    /// And the fader has to be honest about it: its ceiling is what a plan can take, so the
    /// ceiling moves when the scope does.
    func testTheFadersCeilingFollowsTheFilter() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard model.availableKinds.count > 1, model.availableKinds.contains(.video) else {
            return XCTFail("fixture needs videos alongside something else")
        }

        let whole = model.plannableBytes
        model.budgetBytes = Double(whole)
        model.kindFilter = .video

        XCTAssertLessThan(model.plannableBytes, whole)
        XCTAssertLessThanOrEqual(
            Int64(model.budgetBytes),
            model.plannableBytes,
            "a target set against the whole scan must follow the ceiling down"
        )
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

    /// A screen that lets you overrule the app needs a way back, or the choice is a trap.
    func testResetUndoesEveryOverrideAndEveryTick() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard
            let groupID = exactGroupID(model),
            let decision = model.result.decisions.first(where: { $0.id == groupID }),
            let other = decision.allCandidates.first
        else { return XCTFail("fixture has no exact group") }

        XCTAssertFalse(model.hasChangedTheProposal, "nothing has been touched yet")

        model.chooseKeeper(other, inGroup: groupID)
        model.setClearingEverything(true, inGroup: groupID)
        XCTAssertTrue(model.hasChangedTheProposal)

        model.resetToSafeDefaults()

        XCTAssertTrue(model.overrides.isEmpty)
        XCTAssertEqual(model.keeperID(inGroup: groupID), decision.keeperID)
        XCTAssertTrue(model.clearedGroupIDs.isEmpty)
        XCTAssertEqual(model.judgementCallCount, 0, "back to only what costs nothing")
        XCTAssertTrue(model.violations.isEmpty)
        XCTAssertFalse(model.hasChangedTheProposal)
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

        // The regression this caught: the receipt was being written from the candidate list as
        // it stood *after* the deletion, which no longer contains what was deleted. Every line
        // then lost its keeper and defaulted to the riskiest tier.
        XCTAssertTrue(
            receipt.items.allSatisfy { $0.keptInsteadName != "another copy" },
            "each line should name the copy that survived, not a placeholder"
        )
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

    // MARK: - The budget follows what is left

    /// The slider's range is `0...maxReclaimableBytes`, so the user cannot drag past the
    /// ceiling — but deleting moves the ceiling. The target used to survive that: the card read
    /// "I NEED 2.02 GB BACK" with the handle pinned to the end of a track whose end was now a
    /// few megabytes.
    func testDeletingPullsTheTargetBackInsideWhatIsLeft() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        model.budgetBytes = Double(model.maxReclaimableBytes)

        await model.delete()

        XCTAssertFalse(model.outcome?.deletedIDs.isEmpty ?? true, "fixture should delete something")
        XCTAssertLessThanOrEqual(
            Int64(model.budgetBytes),
            model.maxReclaimableBytes,
            "the target may never exceed what is still on offer"
        )
    }

    func testClearingAGroupCannotLeaveTheTargetAboveTheCeiling() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard let groupID = exactGroupID(model) else {
            return XCTFail("fixture has no exact group")
        }

        model.budgetBytes = Double(model.maxReclaimableBytes)
        model.chooseKeeper(model.result.decisions.first { $0.id == groupID }!.allCandidates.first!, inGroup: groupID)

        XCTAssertLessThanOrEqual(Int64(model.budgetBytes), model.maxReclaimableBytes)
    }

    // MARK: - Looking at one kind

    /// The filter is a way of looking, not a change to what was found. The budget slab's
    /// ladder describes the whole scan, so filtering the source would have made the fader's
    /// rungs move whenever somebody tapped "Videos".
    func testFilteringByKindNarrowsTheListAndLeavesTheScanAlone() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())

        let everything = model.sections.flatMap(\.groups).count
        XCTAssertGreaterThan(everything, 0)
        XCTAssertTrue(model.availableKinds.contains(.video), "the fixture has video duplicates")

        model.kindFilter = .video
        let visible = model.kindSections.flatMap { $0.sections.flatMap(\.groups) }

        XCTAssertFalse(visible.isEmpty)
        XCTAssertTrue(visible.allSatisfy { $0.keeper.kind == .video })
        XCTAssertEqual(model.kindSections.map(\.kind), [.video], "only the filtered kind has a section")
        XCTAssertEqual(model.sections.flatMap(\.groups).count, everything, "the scan itself is untouched")
    }

    /// A filter offering a kind the scan never found is a control that can only disappoint.
    func testOnlyKindsThatWereActuallyFoundAreOffered() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        let found = Set(model.sections.flatMap { $0.groups.map { $0.keeper.kind } })

        XCTAssertEqual(Set(model.availableKinds), found)
    }

    /// Kind is the outer level of the list and cost the inner one, and every group has to land
    /// in exactly one place in that structure.
    func testEveryGroupAppearsUnderExactlyOneKindAndOneTier() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())

        let placed = model.kindSections.flatMap { kindSection in
            kindSection.sections.flatMap { section in
                section.groups.map { "\(kindSection.kind.rawValue)|\(section.tier.rawValue)|\($0.id)" }
            }
        }
        XCTAssertEqual(Set(placed).count, placed.count, "a group is listed twice")
        XCTAssertEqual(placed.count, model.sections.flatMap(\.groups).count, "a group went missing")

        for kindSection in model.kindSections {
            for section in kindSection.sections {
                XCTAssertTrue(
                    section.groups.allSatisfy { $0.keeper.kind == kindSection.kind },
                    "a \(kindSection.kind) section holds something else"
                )
            }
        }
    }

    /// Filter to a kind, delete all of it, and the filter used to survive with no control left
    /// on screen to clear it — an empty list over everything else, still hidden.
    func testAFilterWhoseKindIsGoneClearsItself() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        guard let kind = model.availableKinds.first else { return XCTFail("fixture has no kinds") }

        model.kindFilter = kind
        model.setSelected(true, in: model.visibleSections.flatMap(\.groups)[0])
        await model.delete()

        if !model.availableKinds.contains(kind) {
            XCTAssertNil(model.kindFilter, "a filter with nothing behind it has to let go")
        }
    }

    func testTheTallyForEverythingIsTheSumOfItsParts() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter())
        let whole = model.tally(for: nil)
        let parts = model.availableKinds.map { model.tally(for: $0) }

        XCTAssertEqual(whole.items, parts.reduce(0) { $0 + $1.items })
        XCTAssertEqual(whole.bytes, parts.reduce(Int64(0)) { $0 + $1.bytes })
    }

    func testAFailedDeletionIsReported() async {
        let model = ReviewViewModel(result: await makeResult(), deleter: StubDeleter(behaviour: .fail("disk on fire")))
        await model.delete()

        XCTAssertNil(model.outcome)
        XCTAssertEqual(model.failure, "disk on fire")
        XCTAssertFalse(model.isDeleting)
    }
}
