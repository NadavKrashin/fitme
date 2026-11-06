import Foundation

/// A hard reason an outfit can't be suggested at all.
public enum Violation: Equatable, Sendable {
    case structure(String)
    /// Pieces from very different dress codes, e.g. a blazer with gym shorts.
    case formalityClash
    case occasionMismatch
    case missingStyle(StyleTag)
    case tooWarm
    case tooCold
}

/// Hard constraints. Anything that passes here is ranked by `OutfitScorer`.
public enum Rules {
    /// Cheap per-item pre-filter applied before combinations are built.
    public static func isEligible(_ item: Item, for context: OutfitContext) -> Bool {
        guard item.isAvailable, item.category.isCore else { return false }
        let range = context.occasion.formalityRange
        let f = Double(item.formality)
        guard f >= range.lowerBound - 1, f <= range.upperBound + 1 else { return false }

        if let style = context.occasion.requiredStyle,
           !item.styleTags.contains(style),
           !(item.category == .outerwear && item.styleTags.contains(.outdoor)) {
            return false
        }

        let weather = context.weather
        let t = weather.feelsLikeC
        switch item.category {
        case .midLayer:
            return weather.allowsLayers && t < 22
        case .outerwear:
            if t >= 22 {
                return weather.isRainy && item.waterResistant && item.warmth <= 2
            }
            return !(item.warmth >= 4 && t >= 16)
        case .bottom:
            return !(item.warmth <= 1 && t < 16)
        case .shoes:
            return !(item.warmth <= 1 && (t < 15 || weather.isRainy))
        case .top:
            return !(item.warmth >= 3 && t >= 27)
        case .onePiece:
            // A light dress leaves the legs bare, like shorts.
            return !(item.warmth >= 3 && t >= 27) && !(item.warmth <= 1 && t < 15)
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

        if let style = context.occasion.requiredStyle {
            let mustCarry = core.filter { [.top, .bottom, .onePiece, .shoes].contains($0.category) }
            if mustCarry.contains(where: { !$0.styleTags.contains(style) }) {
                result.append(.missingStyle(style))
            }
        }

        if !partial {
            let target = context.weather.upperWarmthTarget
            let warmth = upperWarmth(of: outfit)
            if warmth < target.lowerBound - 1 {
                result.append(.tooCold)
            }
            if warmth > target.upperBound + 1 {
                result.append(.tooWarm)
            }
        }
        return result
    }

    public static func isValid(_ outfit: Outfit, context: OutfitContext) -> Bool {
        violations(of: outfit, context: context).isEmpty
    }

    static func upperWarmth(of outfit: Outfit) -> Int {
        outfit.items
            .filter { [.top, .onePiece, .midLayer, .outerwear].contains($0.category) }
            .map(\.warmth)
            .reduce(0, +)
    }
}
