import Foundation

/// Builds outfits slot by slot (base → shoes → mid layer → outerwear), keeping the best partial outfits at each step.
public struct OutfitGenerator {
    public var scorer: OutfitScorer
    /// How many partial outfits survive each step. Larger is slower but explores more.
    public var beamWidth: Int

    public init(scorer: OutfitScorer = OutfitScorer(), beamWidth: Int = 60) {
        self.scorer = scorer
        self.beamWidth = beamWidth
    }

    /// The best few outfits for a context, picked to be different from each other.
    public func suggest(from closet: [Item], context: OutfitContext, limit: Int = 5, mustInclude: Item? = nil) -> [ScoredOutfit] {
        let candidates = build(from: closet, context: context, mustInclude: mustInclude, beam: beamWidth)
        return Self.diversified(candidates, limit: limit)
    }

    /// Every valid outfit from a small pool (e.g. a packed capsule), best first. No beam pruning.
    public func allOutfits(from pool: [Item], context: OutfitContext, mustInclude: Item? = nil, minScore: Double = 0) -> [ScoredOutfit] {
        build(from: pool, context: context, mustInclude: mustInclude, beam: nil).filter { $0.score >= minScore }
    }

    func build(from pool: [Item], context: OutfitContext, mustInclude: Item?, beam: Int?) -> [ScoredOutfit] {
        var eligible = pool.filter { Rules.isEligible($0, for: context) }
        if let must = mustInclude {
            guard Rules.isEligible(must, for: context) else { return [] }
            eligible.removeAll { $0.category == must.category }
            eligible.append(must)
        }
        var byCategory = Dictionary(grouping: eligible, by: \.category)
        for key in byCategory.keys { byCategory[key]?.sort { $0.id < $1.id } }
        if let must = mustInclude {
            switch must.category {
            case .top, .bottom: byCategory[.onePiece] = []
            case .onePiece: byCategory[.top] = []; byCategory[.bottom] = []
            default: break
            }
        }
        let pool = { (c: ItemCategory) in byCategory[c] ?? [] }

        var partials: [[Item]] = pool(.onePiece).map { [$0] }
        for top in pool(.top) {
            for bottom in pool(.bottom) { partials.append([top, bottom]) }
        }
        partials = prune(partials, context: context, beam: beam)
        partials = prune(extend(partials, with: pool(.shoes), optional: false), context: context, beam: beam)
        partials = prune(extend(partials, with: pool(.midLayer), optional: mustInclude?.category != .midLayer), context: context, beam: beam)
        let finished = extend(partials, with: pool(.outerwear), optional: mustInclude?.category != .outerwear)

        return finished
            .map(Outfit.init(items:))
            .filter { Rules.isValid($0, context: context) }
            .map { ScoredOutfit(outfit: $0, breakdown: scorer.score($0, context: context)) }
            .sorted(by: Self.ranking)
    }

    private func extend(_ partials: [[Item]], with options: [Item], optional: Bool) -> [[Item]] {
        var result: [[Item]] = optional ? partials : []
        for partial in partials {
            for option in options { result.append(partial + [option]) }
        }
        return result
    }

    private func prune(_ partials: [[Item]], context: OutfitContext, beam: Int?) -> [[Item]] {
        let scored = partials
            .map(Outfit.init(items:))
            .filter { Rules.violations(of: $0, context: context, partial: true).isEmpty }
            .map { ScoredOutfit(outfit: $0, breakdown: scorer.score($0, context: context, partial: true)) }
            .sorted(by: Self.ranking)
        let kept = beam.map { Array(scored.prefix($0)) } ?? scored
        return kept.map(\.outfit.items)
    }

    static func ranking(_ a: ScoredOutfit, _ b: ScoredOutfit) -> Bool {
        a.score != b.score ? a.score > b.score : a.id < b.id
    }

    /// Greedy max-marginal-relevance: trade a little score for outfits that don't repeat the same pieces,
    /// and especially not the same top.
    static func diversified(_ ranked: [ScoredOutfit], limit: Int, overlapPenalty: Double = 12, sameBasePenalty: Double = 15) -> [ScoredOutfit] {
        var chosen: [ScoredOutfit] = []
        var remaining = ranked
        while chosen.count < limit, !remaining.isEmpty {
            var bestIndex = 0
            var bestValue = -Double.infinity
            for (i, candidate) in remaining.enumerated() {
                let overlap = chosen.map { jaccard(candidate.outfit, $0.outfit) }.max() ?? 0
                let repeatsBase = chosen.contains { $0.outfit.baseKey == candidate.outfit.baseKey }
                let value = candidate.score - overlapPenalty * overlap - (repeatsBase ? sameBasePenalty : 0)
                if value > bestValue {
                    bestValue = value
                    bestIndex = i
                }
            }
            chosen.append(remaining.remove(at: bestIndex))
        }
        return chosen
    }

    static func jaccard(_ a: Outfit, _ b: Outfit) -> Double {
        let sa = Set(a.items.map(\.id)), sb = Set(b.items.map(\.id))
        return Double(sa.intersection(sb).count) / Double(sa.union(sb).count)
    }
}
