import Foundation

public enum OutfitFeedback: String, Codable, Sendable {
    case liked, disliked, wore
}

/// What the engine has learned from your reactions: which item pairings you like.
public struct StyleProfile: Codable, Equatable, Sendable {
    /// Pair key → affinity in -1...1.
    public var pairAffinity: [String: Double]

    public init(pairAffinity: [String: Double] = [:]) {
        self.pairAffinity = pairAffinity
    }

    public mutating func record(_ feedback: OutfitFeedback, for outfit: Outfit) {
        adjust(outfit, by: Self.delta(for: feedback))
    }

    /// Takes back a reaction (e.g. "undo" on a dislike). Exact unless the affinity had hit its ±1 limit.
    public mutating func revert(_ feedback: OutfitFeedback, for outfit: Outfit) {
        adjust(outfit, by: -Self.delta(for: feedback))
    }

    private mutating func adjust(_ outfit: Outfit, by delta: Double) {
        for (a, b) in Self.pairs(outfit.coreItems) {
            let key = Self.key(a, b)
            let value = min(1, max(-1, (pairAffinity[key] ?? 0) + delta))
            // Drop pairs back at neutral so an undone reaction leaves no trace.
            pairAffinity[key] = abs(value) < 1e-9 ? nil : value
        }
    }

    private static func delta(for feedback: OutfitFeedback) -> Double {
        switch feedback {
        case .liked: 0.2
        case .disliked: -0.25
        case .wore: 0.1
        }
    }

    public func affinity(_ a: Item, _ b: Item) -> Double {
        pairAffinity[Self.key(a, b)] ?? 0
    }

    /// 0...1, where 0.5 means "no opinion yet".
    public func affinityScore(_ core: [Item]) -> Double {
        let pairs = Self.pairs(core)
        guard !pairs.isEmpty else { return 0.5 }
        let mean = pairs.map { affinity($0.0, $0.1) }.reduce(0, +) / Double(pairs.count)
        return 0.5 + 0.5 * mean
    }

    static func key(_ a: Item, _ b: Item) -> String {
        a.id < b.id ? "\(a.id)|\(b.id)" : "\(b.id)|\(a.id)"
    }

    static func pairs(_ items: [Item]) -> [(Item, Item)] {
        var result: [(Item, Item)] = []
        for i in 0 ..< items.count {
            for j in (i + 1) ..< items.count {
                result.append((items[i], items[j]))
            }
        }
        return result
    }
}
