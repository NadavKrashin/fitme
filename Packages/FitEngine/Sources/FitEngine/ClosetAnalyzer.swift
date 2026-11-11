import Foundation

/// What a closet can do as a whole: how many looks each piece is part of, and which missing pieces would unlock the
/// most new outfits.
///
/// A look is a base (top and bottom, or a one-piece) with shoes; layers change with the weather, so the same base and
/// shoes under a coat in winter and on their own in summer count once. A look counts when it makes a good outfit
/// (as good as the packer requires) on at least one typical kind of day. A missing piece is judged by the new
/// outfits it adds: looks on kinds of day the closet can't dress them for yet, so a coat counts for the cold days
/// it makes wearable, not for looks that already work without it. Taste learned from reactions is ignored: this is
/// about what the pieces can do, not what was liked last week.
public struct ClosetAnalyzer: Sendable {
    public var generator: OutfitGenerator
    public var scoreThreshold: Double

    /// Pieces in fewer looks than this are hard to style.
    public static let fewLooks = 3
    /// A hard-to-style piece that a new item gives outfits to counts as this many extra outfits when ranking gaps:
    /// wearing what's already owned matters more than more ways to wear what already works.
    static let rescueValue = 4

    /// A smaller beam than daily suggestions use: every piece is searched in every kind of day it suits, and the
    /// count only needs to tell a workhorse from a piece that matches nothing.
    public init(
        generator: OutfitGenerator = OutfitGenerator(beamWidth: 30),
        scoreThreshold: Double = PackingOptions().scoreThreshold
    ) {
        self.generator = generator
        self.scoreThreshold = scoreThreshold
    }

    /// The kinds of day a closet is judged against. Work, dates and travel dress like smart casual and casual, so
    /// they'd only count the same looks again.
    public static let typicalDays: [OutfitContext] = {
        let weathers = [28.0, 20, 13, 4].map { Weather(feelsLikeC: $0) }
        let everyday: [Occasion] = [.casual, .smartCasual, .formal, .sport]
        let date = Date(timeIntervalSince1970: 0)
        return everyday.flatMap { occasion in
            weathers.map { OutfitContext(occasion: occasion, weather: $0, date: date) }
        } + [OutfitContext(occasion: .beach, weather: weathers[0], date: date)]
    }()

    public func analyze(
        _ closet: [Item],
        candidates: [Item] = GapCatalog.menswear,
        gapLimit: Int = 3
    ) -> ClosetInsights {
        let pieces = Self.wearable(closet)
        var dressingsByItem: [String: Set<Dressing>] = [:]
        for item in pieces where item.category.isCore {
            dressingsByItem[item.id] = Set(goodOutfits(with: item, in: pieces).map(\.dressing))
        }
        let looksByItem = dressingsByItem.mapValues { Set($0.map(\.look)).count }
        let hardToStyle = Set(looksByItem.filter { $0.value < Self.fewLooks }.keys)
        let existing = Set(dressingsByItem.values.joined())

        let gaps = candidates
            .filter { !Self.owns(pieces, $0) }
            .compactMap { gap(for: $0, closet: pieces, existing: existing, hardToStyle: hardToStyle) }
            .sorted { ($0.rank, $1.item.id) > ($1.rank, $0.item.id) }

        return ClosetInsights(
            looksByItem: looksByItem,
            totalLooks: Set(existing.map(\.look)).count,
            gaps: Array(gaps.prefix(gapLimit))
        )
    }

    /// A look worn on one of the typical kinds of day.
    struct Dressing: Hashable {
        let day: Int
        let look: String
    }

    /// Every good outfit that includes `item`, on each typical day it suits.
    func goodOutfits(with item: Item, in pool: [Item]) -> [(dressing: Dressing, outfit: Outfit)] {
        Self.typicalDays.indices.flatMap { day in
            let context = Self.typicalDays[day]
            guard Rules.isEligible(item, for: context) else { return [(dressing: Dressing, outfit: Outfit)]() }
            return generator.build(from: pool, context: context, mustInclude: item, beam: generator.beamWidth)
                .filter { $0.score >= scoreThreshold }
                .map { (Dressing(day: day, look: Self.lookKey($0.outfit)), $0.outfit) }
        }
    }

    private func gap(
        for candidate: Item,
        closet: [Item],
        existing: Set<Dressing>,
        hardToStyle: Set<String>
    ) -> GapSuggestion? {
        var added = Set<Dressing>()
        var partners: [String: Int] = [:]
        for (dressing, outfit) in goodOutfits(with: candidate, in: closet + [candidate])
            where !existing.contains(dressing) {
            // A look can come out twice for one day (with and without a layer); count its partners once.
            guard added.insert(dressing).inserted else { continue }
            for item in outfit.items where item != candidate {
                partners[item.id, default: 0] += 1
            }
        }
        guard !added.isEmpty else { return nil }
        let pairsWith = partners.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        return GapSuggestion(
            item: candidate,
            newOutfits: added.count,
            pairsWith: pairsWith,
            rescues: pairsWith.filter(hardToStyle.contains)
        )
    }

    /// The base and shoes of an outfit, without its weather layers.
    static func lookKey(_ outfit: Outfit) -> String {
        [outfit.onePiece ?? outfit.top, outfit.bottom, outfit.shoes].compactMap { $0?.id }.joined(separator: "+")
    }

    /// Laundry is temporary, so a piece in the wash still counts.
    static func wearable(_ closet: [Item]) -> [Item] {
        closet.map { item in
            var available = item
            available.isAvailable = true
            return available
        }
    }

    /// True when the closet already has something close enough to play the same part: same category, a similar
    /// main color, and about as dressy and warm.
    static func owns(_ closet: [Item], _ candidate: Item) -> Bool {
        guard let color = candidate.primaryColor else { return false }
        return closet.contains { item in
            item.category == candidate.category
                && abs(item.formality - candidate.formality) <= 1
                && abs(item.warmth - candidate.warmth) <= 1
                && (item.primaryColor.map { $0.lab.distance(to: color.lab) < similarColor } ?? false)
        }
    }

    /// OKLab distance under which two colors read as the same in a closet (navy chinos vs. navy jeans).
    private static let similarColor = 0.1
}

public struct ClosetInsights: Equatable, Sendable {
    /// Core item id → how many looks it's part of.
    public let looksByItem: [String: Int]
    /// Distinct looks across the whole closet.
    public let totalLooks: Int
    /// The missing pieces that would add the most, best first.
    public let gaps: [GapSuggestion]

    /// Ids of pieces in fewer than `ClosetAnalyzer.fewLooks` looks, fewest first.
    public var hardToStyle: [String] {
        looksByItem.filter { $0.value < ClosetAnalyzer.fewLooks }
            .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
            .map(\.key)
    }

    /// Ids of the pieces in the most looks, most first.
    public func workhorses(limit: Int = 5) -> [String] {
        Array(looksByItem.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(limit).map(\.key))
    }
}

/// A piece the closet doesn't have, and what it would add.
public struct GapSuggestion: Identifiable, Equatable, Sendable {
    public let item: Item
    /// Looks on kinds of day the closet can't dress them for without it.
    public let newOutfits: Int
    /// Closet item ids it goes with in those outfits, the most outfits together first.
    public let pairsWith: [String]
    /// Hard-to-style pieces it would give new outfits to.
    public let rescues: [String]

    public var id: String {
        item.id
    }

    var rank: Int {
        newOutfits + ClosetAnalyzer.rescueValue * rescues.count
    }
}
