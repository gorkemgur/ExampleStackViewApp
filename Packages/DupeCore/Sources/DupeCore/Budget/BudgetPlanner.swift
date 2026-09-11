import Foundation

/// What one regret tier is worth, in total.
public struct TierSummary: Sendable, Hashable, Identifiable {

    public let tier: RegretTier
    public let itemCount: Int
    public let bytes: Int64
    /// Bytes available from this tier and every cheaper one, so the UI can say
    /// "tiers 0-1 already cover 9.4 GB".
    public let cumulativeBytes: Int64

    public var id: Int { tier.rawValue }

    public init(tier: RegretTier, itemCount: Int, bytes: Int64, cumulativeBytes: Int64) {
        self.tier = tier
        self.itemCount = itemCount
        self.bytes = bytes
        self.cumulativeBytes = cumulativeBytes
    }
}

/// A concrete answer to "I need N bytes back".
public struct BudgetPlan: Sendable, Hashable {

    public let targetBytes: Int64
    public let selected: [DeletionCandidate]
    public let reclaimedBytes: Int64
    /// The worst tier the plan had to reach into. `nil` when the plan is empty.
    public let deepestTier: RegretTier?

    public static let empty = BudgetPlan(targetBytes: 0, selected: [], reclaimedBytes: 0, deepestTier: nil)

    public init(targetBytes: Int64, selected: [DeletionCandidate], reclaimedBytes: Int64, deepestTier: RegretTier?) {
        self.targetBytes = targetBytes
        self.selected = selected
        self.reclaimedBytes = reclaimedBytes
        self.deepestTier = deepestTier
    }

    public var meetsTarget: Bool { reclaimedBytes >= targetBytes }

    public var selectedIDs: Set<String> { Set(selected.map(\.id)) }

    /// How far short the plan falls, zero when the target is met.
    public var shortfallBytes: Int64 { max(targetBytes - reclaimedBytes, 0) }
}

/// Composes the cheapest set of deletions that reaches a byte target.
///
/// Greedy, and deliberately so: the tiers are ordered by what the user loses, and inside a
/// tier the largest items come first because they reach the target with the fewest deletions.
/// An optimal knapsack packing would shave a few megabytes off while asking the user to delete
/// more individual things, which is the wrong trade for this app.
public enum BudgetPlanner {

    public static func summaries(for candidates: [DeletionCandidate]) -> [TierSummary] {
        var counts: [RegretTier: Int] = [:]
        var bytes: [RegretTier: Int64] = [:]

        for candidate in candidates {
            counts[candidate.tier, default: 0] += 1
            bytes[candidate.tier, default: 0] += candidate.bytes
        }

        var cumulative: Int64 = 0
        return RegretTier.allCases.compactMap { tier in
            guard let count = counts[tier], count > 0 else { return nil }
            let tierBytes = bytes[tier] ?? 0
            cumulative += tierBytes
            return TierSummary(tier: tier, itemCount: count, bytes: tierBytes, cumulativeBytes: cumulative)
        }
    }

    public static func plan(
        target targetBytes: Int64,
        candidates: [DeletionCandidate],
        allowedTiers: Set<RegretTier> = Set(RegretTier.allCases)
    ) -> BudgetPlan {

        guard targetBytes > 0 else {
            return BudgetPlan(targetBytes: max(targetBytes, 0), selected: [], reclaimedBytes: 0, deepestTier: nil)
        }

        let ordered = candidates
            .filter { allowedTiers.contains($0.tier) && $0.bytes > 0 }
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
                return lhs.id < rhs.id
            }

        var selected: [DeletionCandidate] = []
        var reclaimed: Int64 = 0
        var deepest: RegretTier?

        for candidate in ordered {
            if reclaimed >= targetBytes { break }
            selected.append(candidate)
            reclaimed += candidate.bytes
            deepest = max(deepest ?? candidate.tier, candidate.tier)
        }

        return BudgetPlan(
            targetBytes: targetBytes,
            selected: selected,
            reclaimedBytes: reclaimed,
            deepestTier: deepest
        )
    }

    /// Everything the engine is willing to tick without a human looking, which is the app's
    /// default state before the user touches the budget slider.
    public static func losslessPlan(candidates: [DeletionCandidate]) -> BudgetPlan {
        let selected = candidates
            .filter { $0.isPreSelected }
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
                return lhs.id < rhs.id
            }
        let reclaimed = selected.reduce(Int64(0)) { $0 + $1.bytes }
        return BudgetPlan(
            targetBytes: reclaimed,
            selected: selected,
            reclaimedBytes: reclaimed,
            deepestTier: selected.map(\.tier).max()
        )
    }
}
