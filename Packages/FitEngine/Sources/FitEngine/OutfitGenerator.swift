import Foundation

/// Builds outfits slot by slot (base → shoes → mid layer → outerwear), keeping the best partial outfits at each step.
public struct OutfitGenerator: Sendable {
    public var scorer: OutfitScorer
    /// How many partial outfits survive each step. Larger is slower but explores more.
    public var beamWidth: Int

    public init(scorer: OutfitScorer = OutfitScorer(), beamWidth: Int = 60) {
        self.scorer = scorer
        self.beamWidth = beamWidth
    }

    /// The best few outfits for a context, picked to be different from each other.
    public func suggest(
        from closet: [Item],
        context: OutfitContext,
        limit: Int = 5,
        mustInclude: Item? = nil
    ) -> [ScoredOutfit] {
        let candidates = build(from: closet, context: context, mustInclude: mustInclude, beam: beamWidth)
        return Self.diversified(candidates, limit: limit)
    }

    /// Every valid outfit from a small pool (e.g. a packed capsule), best first. No beam pruning.
    public func allOutfits(
        from pool: [Item],
        context: OutfitContext,
        mustInclude: Item? = nil,
        minScore: Double = 0
    ) -> [ScoredOutfit] {
        build(from: pool, context: context, mustInclude: mustInclude, beam: nil).filter { $0.score >= minScore }
    }

    /// Other outfits from a small pool to replace `current`, picked to differ from it (and each other), not just
    /// swap its shoes.
    public func alternatives(
        to current: Outfit,
        from pool: [Item],
        context: OutfitContext,
        limit: Int = 6
    ) -> [ScoredOutfit] {
        let others = allOutfits(from: pool, context: context).filter { $0.id != current.id }
        return Self.diversified(others, limit: limit, avoiding: [current])
    }

    /// The same outfit with one piece replaced by another from the closet, best first. For a layer, going without
    /// it is offered too when the outfit still works.
    public func swaps(
        replacing piece: Item,
        in outfit: Outfit,
        from closet: [Item],
        context: OutfitContext,
        limit: Int = 8
    ) -> [ScoredOutfit] {
        let rest = outfit.items.filter { $0 != piece }
        let replacements = closet
            .filter { $0.category == piece.category && $0 != piece && Rules.isEligible($0, for: context) }
            .map { Outfit(items: rest + [$0]) }
        let withoutLayer = [ItemCategory.midLayer, .outerwear].contains(piece.category) ? [Outfit(items: rest)] : []
        return (replacements + withoutLayer)
            .filter { Rules.isValid($0, context: context) }
            .map { ScoredOutfit(outfit: $0, breakdown: scorer.score($0, context: context)) }
            .sorted(by: Self.ranking(on: context.date))
            .prefix(limit)
            .map(\.self)
    }

    func build(from pool: [Item], context: OutfitContext, mustInclude: Item?, beam: Int?) -> [ScoredOutfit] {
        var eligible = pool.filter { Rules.isEligible($0, for: context) }
        if let must = mustInclude {
            guard Rules.isEligible(must, for: context) else { return [] }
            eligible.removeAll { $0.category == must.category }
            eligible.append(must)
        }
        var byCategory = Dictionary(grouping: eligible, by: \.category)
        for key in byCategory.keys {
            byCategory[key]?.sort { $0.id < $1.id }
        }
        if let must = mustInclude {
            switch must.category {
            case .top, .bottom: byCategory[.onePiece] = []
            case .onePiece: byCategory[.top] = []
                byCategory[.bottom] = []
            default: break
            }
        }
        let pool = { (c: ItemCategory) in byCategory[c] ?? [] }

        var partials: [[Item]] = pool(.onePiece).map { [$0] }
        for top in pool(.top) {
            for bottom in pool(.bottom) {
                partials.append([top, bottom])
            }
        }
        partials = prune(partials, context: context, beam: beam)
        partials = prune(extend(partials, with: pool(.shoes), optional: false), context: context, beam: beam)
        partials = prune(
            extend(partials, with: pool(.midLayer), optional: mustInclude?.category != .midLayer),
            context: context,
            beam: beam
        )
        let finished = extend(partials, with: pool(.outerwear), optional: mustInclude?.category != .outerwear)

        return finished
            .map(Outfit.init(items:))
            .filter { Rules.isValid($0, context: context) }
            .map { ScoredOutfit(outfit: $0, breakdown: scorer.score($0, context: context)) }
            .sorted(by: Self.ranking(on: context.date))
    }

    private func extend(_ partials: [[Item]], with options: [Item], optional: Bool) -> [[Item]] {
        var result: [[Item]] = optional ? partials : []
        for partial in partials {
            for option in options {
                result.append(partial + [option])
            }
        }
        return result
    }

    private func prune(_ partials: [[Item]], context: OutfitContext, beam: Int?) -> [[Item]] {
        let scored = partials
            .map(Outfit.init(items:))
            .filter { Rules.violations(of: $0, context: context, partial: true).isEmpty }
            .map { ScoredOutfit(outfit: $0, breakdown: scorer.score($0, context: context, partial: true)) }
            .sorted(by: Self.ranking(on: context.date))
        let kept = beam.map { Array(scored.prefix($0)) } ?? scored
        return kept.map(\.outfit.items)
    }

    /// Best score first, ties by ID. Stable, for packing, where the same inputs must give the same bag.
    static func ranking(_ a: ScoredOutfit, _ b: ScoredOutfit) -> Bool {
        a.score != b.score ? a.score > b.score : a.id < b.id
    }

    /// Best score first, ties shuffled by the day: outfits that score the same take turns from one day to the next,
    /// instead of the lowest item IDs (often the same pair of shoes) winning every tie.
    static func ranking(on date: Date) -> @Sendable (ScoredOutfit, ScoredOutfit) -> Bool {
        let day = Int((date.timeIntervalSince1970 / 86400).rounded(.down))
        return { a, b in
            guard a.score == b.score else { return a.score > b.score }
            let (keyA, keyB) = (tieBreakKey(a.id, day: day), tieBreakKey(b.id, day: day))
            return keyA != keyB ? keyA < keyB : a.id < b.id
        }
    }

    /// FNV-1a over the day and the outfit: the same on every launch, unlike `Hasher`.
    static func tieBreakKey(_ id: String, day: Int) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(day)|\(id)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        return hash
    }

    /// Greedy max-marginal-relevance: trade a little score for outfits that don't repeat the same pieces,
    /// and especially not the same top. Outfits in `avoiding` count as already chosen but aren't returned.
    static func diversified(
        _ ranked: [ScoredOutfit],
        limit: Int,
        avoiding: [Outfit] = [],
        overlapPenalty: Double = 12,
        sameBasePenalty: Double = 15
    ) -> [ScoredOutfit] {
        var chosen: [ScoredOutfit] = []
        var taken = avoiding
        var remaining = ranked
        while chosen.count < limit, !remaining.isEmpty {
            var bestIndex = 0
            var bestValue = -Double.infinity
            for (i, candidate) in remaining.enumerated() {
                let overlap = taken.map { jaccard(candidate.outfit, $0) }.max() ?? 0
                let repeatsBase = taken.contains { $0.baseKey == candidate.outfit.baseKey }
                let value = candidate.score - overlapPenalty * overlap - (repeatsBase ? sameBasePenalty : 0)
                if value > bestValue {
                    bestValue = value
                    bestIndex = i
                }
            }
            let pick = remaining.remove(at: bestIndex)
            chosen.append(pick)
            taken.append(pick.outfit)
        }
        return chosen
    }

    /// How much two outfits share, 0...1, weighted by how much each piece makes an outfit look different: the top and
    /// trousers do; the same shoes or jacket on two days is normal.
    static func jaccard(_ a: Outfit, _ b: Outfit) -> Double {
        let ia = Set(a.items), ib = Set(b.items)
        let weight = { (items: Set<Item>) in items.map { Self.distinctness($0.category) }.reduce(0, +) }
        let union = weight(ia.union(ib))
        return union > 0 ? weight(ia.intersection(ib)) / union : 0
    }

    private static func distinctness(_ category: ItemCategory) -> Double {
        switch category {
        case .top, .onePiece: 3
        case .bottom: 2
        case .midLayer, .outerwear: 1.5
        case .shoes, .bag, .accessory: 1
        }
    }
}
