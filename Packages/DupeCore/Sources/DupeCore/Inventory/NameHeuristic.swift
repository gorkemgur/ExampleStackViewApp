import Foundation

/// Files that look like copies of one another by name alone.
///
/// Deliberately kept out of the deletion path. "report.pdf" and "report (1).pdf" are probably
/// related, but a name is not evidence about content, and this app does not delete on probably.
/// The clusters exist so a person can go and look.
public struct NameCluster: Sendable, Hashable, Identifiable {

    public let canonicalName: String
    public let itemIDs: [String]

    public var id: String { canonicalName }

    public init(canonicalName: String, itemIDs: [String]) {
        self.canonicalName = canonicalName
        self.itemIDs = itemIDs
    }
}

public enum NameHeuristic {

    /// Strips the decorations an operating system adds when it will not overwrite a file:
    /// "report (1).pdf", "report copy.pdf" and "report copy 3.pdf" all reduce to "report.pdf".
    ///
    /// Only unambiguous copy markers are stripped. A trailing "-2" is *not* one of them:
    /// cameras name files that way, and reducing "IMG-1234" and "IMG-5678" to the same thing
    /// would cluster unrelated photos.
    public static func canonicalName(_ name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension.lowercased()
        var stem = url.deletingPathExtension().lastPathComponent

        var previous: String
        repeat {
            previous = stem
            for pattern in copyPatterns {
                let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
                stem = pattern.stringByReplacingMatches(in: stem, range: range, withTemplate: "")
            }
            stem = stem.trimmingCharacters(in: .whitespaces)
        } while stem != previous && !stem.isEmpty

        let base = stem.lowercased()
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    /// True when the name carries one of those decorations.
    public static func looksLikeCopy(_ name: String) -> Bool {
        let plain = URL(fileURLWithPath: name).lastPathComponent.lowercased()
        return canonicalName(plain) != plain
    }

    /// Groups of two or more items whose names reduce to the same thing.
    ///
    /// - Parameter excluding: items already accounted for by content-based grouping. A pair the
    ///   engine has proven identical does not need a second, weaker explanation.
    public static func clusters(
        for items: [MediaItem],
        excluding excludedIDs: Set<String> = []
    ) -> [NameCluster] {

        var buckets: [String: [String]] = [:]
        for item in items where !excludedIDs.contains(item.id) {
            let name = item.displayName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            buckets[canonicalName(name), default: []].append(item.id)
        }

        return buckets
            .filter { $0.value.count > 1 }
            .map { NameCluster(canonicalName: $0.key, itemIDs: $0.value.sorted()) }
            .sorted { $0.canonicalName < $1.canonicalName }
    }

    // MARK: - Patterns

    private static let copyPatterns: [NSRegularExpression] = {
        let sources = [
            #"\s*\(\d+\)$"#,            // report (1)
            #"\s*[-–]?\s*copy(\s+\d+)?$"#  // report copy, report - copy, report copy 2
        ]
        return sources.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }()
}
