import Foundation

/// A hard reason an outfit can't be suggested at all.
public enum Violation: Equatable, Sendable {
    case structure(String)
    /// Pieces from very different dress codes, e.g. a blazer with gym shorts.
    case formalityClash
    case occasionMismatch
    /// A piece without the style the occasion calls for, e.g. jeans for a run.
    case missingStyle
    case tooWarm
    case tooCold
    /// A jacket over a mid layer on a day too mild for both.
    case tooManyLayers
    /// A layer the day doesn't call for: dry, and warm enough without it.
    case unneededLayer
    /// A suit jacket with trousers that aren't its own.
    case splitSuit
}

/// Hard constraints. Anything that passes here is ranked by `OutfitScorer`.
public enum Rules {
    /// Cheap per-item pre-filter applied before combinations are built.
    public static func isEligible(_ item: Item, for context: OutfitContext) -> Bool {
        guard item.isAvailable, item.category.isCore else { return false }
        let range = context.occasion.formalityRange
        let f = Double(item.formality)
        guard f >= range.lowerBound - 1, f <= range.upperBound + 1,
              suitsDressCode(item, context: context)
        else { return false }

        let styles = context.occasion.requiredStyles
        if !styles.isEmpty, item.styleTags.isDisjoint(with: styles),
           !(item.category == .outerwear && item.styleTags.contains(.outdoor)) {
            return false
        }

        let weather = context.weather
        let legs = weather.legsC
        switch item.category {
        case .midLayer:
            // Formal wears its tailored jacket in any weather.
            return context.occasion == .formal || (weather.allowsLayers && weather.coolestC < 22)
        case .outerwear:
            if weather.coolestC >= 22 {
                return weather.isRainy && item.waterResistant && item.warmth <= 2
            }
            return !(item.warmth >= 4 && weather.coolestC >= 16)
        case .bottom:
            // Shorts from the low twenties (guides put them at 23° and up, with long sleeves a little lower).
            return !(item.warmth <= 1 && legs < 20) && !(item.warmth >= 4 && legs >= 24)
        case .shoes:
            // Sandals on warm dry days; boots for cool or wet ones.
            return !(item.warmth <= 1 && (legs < 20 || weather.isRainy))
                && !(item.warmth >= 4 && legs >= 24 && !weather.isRainy)
        case .top:
            // The base stays on all day, so it must suit the warmest part of it.
            return !(item.warmth >= 3 && weather.warmestC >= 24)
        case .onePiece:
            // A light dress leaves the legs bare, like shorts.
            return !(item.warmth >= 3 && weather.warmestC >= 27) && !(item.warmth <= 1 && legs < 15)
        case .bag, .accessory:
            return false
        }
    }

    /// `partial` skips checks that need the finished outfit (shoes present, weather layering).
    public static func violations(of outfit: Outfit, context: OutfitContext, partial: Bool = false) -> [Violation] {
        var result: [Violation] = []
        let count = { (c: ItemCategory) in outfit.items(in: c).count }

        let separates = count(.top) == 1 && count(.bottom) == 1 && count(.onePiece) == 0
        let dress = count(.onePiece) == 1 && count(.top) == 0 && count(.bottom) == 0
        if !(separates || dress) {
            result.append(.structure("needs a top and bottom, or a one-piece"))
        }
        if count(.midLayer) > 1 || count(.outerwear) > 1 {
            result.append(.structure("too many layers"))
        }
        if count(.midLayer) == 1, count(.outerwear) == 1, !context.weather.allowsStackedLayers {
            result.append(.tooManyLayers)
        }
        if !partial, count(.shoes) != 1 {
            result.append(.structure("needs one pair of shoes"))
        }

        let core = outfit.coreItems
        let formalities = core.map(\.formality)
        if let lo = formalities.min(), let hi = formalities.max(), hi - lo >= 3 {
            result.append(.formalityClash)
        }

        if !core.isEmpty {
            let mean = Double(formalities.reduce(0, +)) / Double(core.count)
            let range = context.occasion.formalityRange
            let underdressedShoes = context.occasion == .formal && (outfit.shoes?.formality ?? 5) < 4
            if mean < range.lowerBound - 0.5 || mean > range.upperBound + 0.5 || underdressedShoes {
                result.append(.occasionMismatch)
            }
        }

        let styles = context.occasion.requiredStyles
        if !styles.isEmpty {
            let mustCarry = core.filter { [.top, .bottom, .onePiece, .shoes].contains($0.category) }
            if mustCarry.contains(where: { $0.styleTags.isDisjoint(with: styles) }) {
                result.append(.missingStyle)
            }
        }

        result += dressCodeViolations(of: outfit, occasion: context.occasion, partial: partial)
        if !partial {
            result += weatherViolations(of: outfit, context: context)
        }
        return result
    }

    private static func weatherViolations(of outfit: Outfit, context: OutfitContext) -> [Violation] {
        let weather = context.weather
        let cool = Weather.warmthTarget(at: weather.coolestC)
        let warm = Weather.warmthTarget(at: weather.warmestC)
        var result: [Violation] = []
        if upperWarmth(of: outfit) < cool.lowerBound - 1 {
            result.append(.tooCold)
        }
        let tooWarmWhenCool = weather.swing != nil && dressedWarmth(of: outfit, context: context) > cool.upperBound + 1
        if dressedWarmth(of: base(of: outfit, weather: weather), context: context) > warm.upperBound + 1
            || tooWarmWhenCool {
            result.append(.tooWarm)
        }
        let jacket = dressCodeJacket(in: outfit, occasion: context.occasion)
        if hasUnneededLayer(Outfit(items: outfit.items.filter { $0 != jacket }), weather: weather) {
            result.append(.unneededLayer)
        }
        return result
    }

    /// What stays on all day: on a day that swings, the outfit without the layers that come off.
    static func base(of outfit: Outfit, weather: Weather) -> Outfit {
        guard weather.swing != nil else { return outfit }
        return Outfit(items: outfit.items.filter { $0.category != .midLayer && $0.category != .outerwear })
    }

    /// Upper-body warmth as worn, judged against the heat: a formal event's tailored jacket doesn't count, since the
    /// dress code asks for it whatever the weather.
    static func dressedWarmth(of outfit: Outfit, context: OutfitContext) -> Int {
        upperWarmth(of: outfit) - (dressCodeJacket(in: outfit, occasion: context.occasion)?.warmth ?? 0)
    }

    public static func isValid(_ outfit: Outfit, context: OutfitContext) -> Bool {
        violations(of: outfit, context: context).isEmpty
    }

    /// On a day too mild to stack layers, a layer has to earn its place: the outfit would be too cool without it at the
    /// coolest part of the day, or it's the rain cover on a wet day. A rain shell over a hoodie on a dry 21° day does
    /// neither.
    static func hasUnneededLayer(_ outfit: Outfit, weather: Weather) -> Bool {
        guard !weather.allowsStackedLayers else { return false }
        let warmth = upperWarmth(of: outfit)
        return [outfit.midLayer, outfit.outerwear].compactMap(\.self).contains { layer in
            let isRainCover = weather.isRainy && layer.category == .outerwear && layer.waterResistant
            return !isRainCover && warmth - layer.warmth >= Weather.warmthTarget(at: weather.coolestC).lowerBound
        }
    }

    static func upperWarmth(of outfit: Outfit) -> Int {
        outfit.items
            .filter { [.top, .onePiece, .midLayer, .outerwear].contains($0.category) }
            .map(\.warmth)
            .reduce(0, +)
    }
}
