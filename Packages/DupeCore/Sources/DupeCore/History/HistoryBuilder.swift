import Foundation

/// Turns live engine state into the frozen records the history keeps.
public enum HistoryBuilder {

    public static func scanRecord(
        result: ScanResult,
        itemsScanned: Int,
        startedAt: Date,
        finishedAt: Date
    ) -> ScanRecord {
        ScanRecord(
            startedAt: startedAt,
            finishedAt: finishedAt,
            itemsScanned: itemsScanned,
            groupsFound: result.groups.count,
            reclaimableBytes: result.reclaimableBytes,
            tiers: result.tierSummaries.map {
                TierTotal(tier: $0.tier, itemCount: $0.itemCount, bytes: $0.bytes)
            },
            cloudOnlyCount: result.cloudOnlyIDs.count
        )
    }

    /// A receipt for one deletion.
    ///
    /// Names are copied in rather than referenced. The whole point of a receipt is that it
    /// still reads correctly after the thing it describes is gone.
    /// `candidates` defaults to the scan's own, but the caller passes the revised list when the
    /// user overruled a survivor or cleared a group — otherwise the receipt names a copy that was
    /// deleted, or says something was kept when nothing was.
    public static func deletionRecord(
        deletedIDs: [String],
        result: ScanResult,
        savings: SavingsBreakdown,
        performedAt: Date,
        candidates: [DeletionCandidate]? = nil
    ) -> DeletionRecord {

        let candidatesByID = Dictionary(
            (candidates ?? result.candidates).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let deleted = Set(deletedIDs)

        let items: [DeletedItemRecord] = deletedIDs.sorted().compactMap { id in
            guard let item = result.items[id] else { return nil }
            // A survivor that was itself deleted is not what was kept in its place; saying so
            // would be the receipt telling a story the library cannot confirm.
            let keeperName: String
            if let candidate = candidatesByID[id] {
                if candidate.keeperID == id || deleted.contains(candidate.keeperID) {
                    keeperName = "nothing — every copy went"
                } else {
                    keeperName = result.items[candidate.keeperID]?.displayName ?? "another copy"
                }
            } else {
                keeperName = "another copy"
            }
            let candidate = candidatesByID[id]

            return DeletedItemRecord(
                id: id,
                displayName: item.displayName,
                bytes: item.totalByteSize,
                kind: item.kind,
                tier: candidate?.tier ?? .similar,
                keptInsteadName: keeperName
            )
        }

        return DeletionRecord(
            performedAt: performedAt,
            items: items,
            deferredBytes: savings.deferredBytes,
            immediateBytes: savings.immediateBytes
        )
    }
}
