import Foundation

public enum OutfitFeedback: String, Codable, Sendable {
    case liked, disliked, wore
}

/// What the engine has learned from your reactions: which item pairings you like, and, more loosely, which color
/// pairings, so a liked navy-and-white outfit also lifts other navy-and-white outfits.
public struct StyleProfile: Codable, Equatable, Sendable {
    /// Item pair key → affinity in -1...1.
    public var pairAffinity: [String: Double]
    /// Color family pair key ("navy|white") → affinity in -1...1.
    public var colorAffinity: [String: Double]

    public init(pairAffinity: [String: Double] = [:], colorAffinity: [String: Double] = [:]) {
        self.pairAffinity = pairAffinity
        self.colorAffinity = colorAffinity
    }

    /// Profiles saved before color learning existed have no `colorAffinity`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            pairAffinity: c.decode([String: Double].self, forKey: .pairAffinity),
            colorAffinity: c.decodeIfPresent([String: Double].self, forKey: .colorAffinity) ?? [:]
        )
    }

    public var isEmpty: Bool {
        pairAffinity.isEmpty && colorAffinity.isEmpty
    }

    public mutating func record(_ feedback: OutfitFeedback, for outfit: Outfit) {
        adjust(outfit, by: Self.Rate(feedback), sign: 1)
    }

    /// Takes back a reaction (e.g. "undo" on a dislike). Exact unless an affinity had hit its ±1 limit.
    public mutating func revert(_ feedback: OutfitFeedback, for outfit: Outfit) {
        adjust(outfit, by: Self.Rate(feedback), sign: -1)
    }

    private mutating func adjust(_ outfit: Outfit, by rate: Rate, sign: Double) {
        for (a, b) in Self.pairs(outfit.coreItems) {
            Self.nudge(&pairAffinity, Self.key(a, b), by: sign * rate.items)
            if let colors = Self.colorKey(a, b) {
                Self.nudge(&colorAffinity, colors, by: sign * rate.colors)
            }
        }
    }

    private static func nudge(_ affinities: inout [String: Double], _ key: String, by delta: Double) {
        let value = min(1, max(-1, (affinities[key] ?? 0) + delta))
        // Drop pairs back at neutral so an undone reaction leaves no trace.
        affinities[key] = abs(value) < 1e-9 ? nil : value
    }

    /// How far one reaction moves each pairing. A dislike counts for more than a like: a suggestion you rejected
    /// should not come back, while a liked one only needs to come up a little more often. Color pairings learn
    /// slowly, from the pattern across many reactions rather than any single outfit.
    struct Rate {
        let items: Double
        let colors: Double

        init(_ feedback: OutfitFeedback) {
            switch feedback {
            case .liked: (items, colors) = (0.25, 0.05)
            case .disliked: (items, colors) = (-0.4, -0.05)
            case .wore: (items, colors) = (0.15, 0.03)
            }
        }
    }

    public func affinity(_ a: Item, _ b: Item) -> Double {
        pairAffinity[Self.key(a, b)] ?? 0
    }

    /// 0...1, where 0.5 means "no opinion yet". Pair opinions add up, so an outfit you liked as a whole scores
    /// higher than one sharing only its shoes with it; `tanh` keeps the total in range.
    public func affinityScore(_ core: [Item]) -> Double {
        var signal = 0.0
        for (a, b) in Self.pairs(core) {
            signal += affinity(a, b)
            if let colors = Self.colorKey(a, b) {
                signal += colorAffinity[colors] ?? 0
            }
        }
        return 0.5 + 0.5 * tanh(signal)
    }

    /// Color pairings learned strongly enough to mention, strongest first.
    public func colorPairings(minimumStrength: Double = 0.1) -> (liked: [ColorPairing], disliked: [ColorPairing]) {
        let all = colorAffinity.compactMap { key, value -> ColorPairing? in
            let parts = key.split(separator: "|").compactMap { ColorFamily(rawValue: String($0)) }
            guard parts.count == 2, abs(value) >= minimumStrength else { return nil }
            return ColorPairing(first: parts[0], second: parts[1], affinity: value)
        }
        let byStrength = all.sorted { (abs($0.affinity), $0.id) > (abs($1.affinity), $1.id) }
        return (byStrength.filter { $0.affinity > 0 }, byStrength.filter { $0.affinity < 0 })
    }

    static func key(_ a: Item, _ b: Item) -> String {
        a.id < b.id ? "\(a.id)|\(b.id)" : "\(b.id)|\(a.id)"
    }

    static func colorKey(_ a: Item, _ b: Item) -> String? {
        guard let first = a.primaryColor?.family, let second = b.primaryColor?.family else { return nil }
        let names = [first.rawValue, second.rawValue].sorted()
        return "\(names[0])|\(names[1])"
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

/// Two color families and how much you like seeing them together, in -1...1.
public struct ColorPairing: Identifiable, Hashable, Sendable {
    public let first: ColorFamily
    public let second: ColorFamily
    public let affinity: Double

    public var id: String {
        "\(first.rawValue)|\(second.rawValue)"
    }
}
