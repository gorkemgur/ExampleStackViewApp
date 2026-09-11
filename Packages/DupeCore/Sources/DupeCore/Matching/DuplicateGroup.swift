import Foundation

/// How confident the engine is that two items are the same thing.
public enum DuplicateRelation: Int, Sendable, Codable, CaseIterable, Comparable {
    /// Byte-identical originals. Equality here is a true equivalence relation.
    case exact
    /// Same capture re-encoded: a resend, a transcode, an export at another size.
    case nearExact
    /// Visually alike. Never auto-selected for deletion.
    case similar

    public static func < (lhs: DuplicateRelation, rhs: DuplicateRelation) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// An undirected similarity link. Endpoints are normalised so `(a, b)` and `(b, a)` are one edge.
public struct SimilarityEdge: Sendable, Hashable {

    public let a: String
    public let b: String
    /// Hamming bits between the two perceptual hashes.
    public let distance: Int

    public init(a: String, b: String, distance: Int) {
        if a <= b {
            self.a = a
            self.b = b
        } else {
            self.a = b
            self.b = a
        }
        self.distance = distance
    }

    public func other(than id: String) -> String? {
        if id == a { return b }
        if id == b { return a }
        return nil
    }
}

/// A set of items the engine believes are the same content.
public struct DuplicateGroup: Sendable, Hashable, Identifiable {

    public let id: String
    public let relation: DuplicateRelation
    /// The item every other member was compared against directly. For non-exact groups this
    /// is also the item that must survive, so no deletion is ever justified transitively.
    public let seedID: String
    /// All members, `seedID` first, the rest ordered deterministically.
    public let itemIDs: [String]

    public init(id: String, relation: DuplicateRelation, seedID: String, itemIDs: [String]) {
        self.id = id
        self.relation = relation
        self.seedID = seedID
        self.itemIDs = itemIDs
    }

    public var count: Int { itemIDs.count }
}
