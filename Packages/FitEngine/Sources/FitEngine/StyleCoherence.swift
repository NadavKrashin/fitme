import Foundation

public extension StyleTag {
    /// How well two aesthetics mix in one outfit, 0...1, after how stylists combine them: classic tailoring with
    /// minimal or preppy pieces, streetwear with sportswear, outdoor workwear with street or classic, boho with
    /// romantic. Technical sportswear with tailoring, or with soft romantic and boho pieces, clashes. Pairs the
    /// guides don't single out mix reasonably (0.85).
    static func compatibility(_ a: StyleTag, _ b: StyleTag) -> Double {
        if a == b {
            return 1
        }
        return pairings[Set([a, b])] ?? 0.85
    }

    private static let pairings: [Set<StyleTag>: Double] = [
        [.classic, .minimal]: 1, [.classic, .preppy]: 1, [.minimal, .street]: 1, [.minimal, .edgy]: 1,
        [.minimal, .preppy]: 1, [.street, .sporty]: 1, [.street, .edgy]: 1, [.outdoor, .street]: 1,
        [.outdoor, .sporty]: 1, [.boho, .romantic]: 1,
        [.classic, .edgy]: 0.9, [.outdoor, .classic]: 0.9, [.minimal, .boho]: 0.9,
        [.preppy, .street]: 0.75, [.preppy, .edgy]: 0.7, [.romantic, .street]: 0.7, [.sporty, .preppy]: 0.7,
        [.sporty, .classic]: 0.6, [.sporty, .boho]: 0.5, [.outdoor, .boho]: 0.5,
        [.sporty, .romantic]: 0.4, [.outdoor, .romantic]: 0.4,
    ]
}

public extension OutfitScorer {
    /// Whether the pieces come from aesthetics that belong together: each pair of tagged pieces scores its best-mixing
    /// pair of tags, and the weakest pair counts as much as the average. Untagged pieces go with anything.
    static func styleCoherence(_ core: [Item]) -> Double {
        let tagged = core.map(\.styleTags).filter { !$0.isEmpty }
        var pairs: [Double] = []
        for (i, a) in tagged.enumerated() {
            for b in tagged[(i + 1)...] {
                pairs.append(a.flatMap { x in b.map { y in StyleTag.compatibility(x, y) } }.max() ?? 1)
            }
        }
        guard let weakest = pairs.min() else { return 1 }
        return 0.5 * pairs.reduce(0, +) / Double(pairs.count) + 0.5 * weakest
    }
}
