import Foundation

public struct ScoreWeights: Equatable {
    public var color = 0.28
    public var pattern = 0.12
    public var formality = 0.15
    public var occasion = 0.12
    public var weather = 0.13
    public var fit = 0.06
    public var statement = 0.06
    public var affinity = 0.05
    public var novelty = 0.03

    public init() {}
}

/// Each component is 0...1; `total` is the weighted blend on a 0...100 scale.
public struct ScoreBreakdown: Equatable {
    public var color: Double
    public var pattern: Double
    public var formality: Double
    public var occasion: Double
    public var weather: Double
    public var fit: Double
    public var statement: Double
    public var affinity: Double
    public var novelty: Double
    public var total: Double
}

/// Soft styling judgement: how good an outfit looks, assuming it already passed `Rules`.
public struct OutfitScorer {
    public var weights: ScoreWeights

    public init(weights: ScoreWeights = ScoreWeights()) {
        self.weights = weights
    }

    /// `partial` scores an outfit still being assembled, so weather is left neutral.
    public func score(_ outfit: Outfit, context: OutfitContext, partial: Bool = false) -> ScoreBreakdown {
        let core = outfit.coreItems
        let w = weights
        var b = ScoreBreakdown(
            color: Self.colorHarmony(outfit),
            pattern: Self.patternBalance(core),
            formality: Self.formalityCohesion(core),
            occasion: Self.occasionFit(core, occasion: context.occasion),
            weather: partial ? 1 : Self.weatherFit(outfit, weather: context.weather),
            fit: Self.fitBalance(outfit),
            statement: Self.statementBudget(core),
            affinity: context.profile?.affinityScore(core) ?? 0.5,
            novelty: Self.novelty(core, on: context.date),
            total: 0
        )
        let weighted = w.color * b.color + w.pattern * b.pattern + w.formality * b.formality
            + w.occasion * b.occasion + w.weather * b.weather + w.fit * b.fit
            + w.statement * b.statement + w.affinity * b.affinity + w.novelty * b.novelty
        let sum = w.color + w.pattern + w.formality + w.occasion + w.weather + w.fit
            + w.statement + w.affinity + w.novelty
        b.total = weighted / sum * 100
        return b
    }

    // MARK: Components

    /// Neutrals go with anything; one accent color family is the safest win; several families must relate by hue.
    public static func colorHarmony(_ outfit: Outfit) -> Double {
        let chromatic = outfit.coreItems
            .flatMap(\.significantColors)
            .map(\.lch)
            .filter { $0.neutrality == .chromatic }

        // Colors within ~25° of hue read as one family (tonal / monochrome dressing).
        var families: [OKLCH] = []
        for color in chromatic where !families.contains(where: { OKLCH.hueDistance($0.h, color.h) <= 25 }) {
            families.append(color)
        }

        var score: Double
        switch families.count {
        case 0:
            score = 0.85
        case 1:
            score = 0.95
        default:
            var pairs: [Double] = []
            for i in 0..<families.count {
                for j in (i + 1)..<families.count {
                    pairs.append(huePairScore(families[i], families[j]))
                }
            }
            score = pairs.reduce(0, +) / Double(pairs.count) - 0.12 * Double(families.count - 2)
        }

        // Different hues at the same lightness between top and bottom look muddy.
        if let upper = (outfit.top ?? outfit.onePiece)?.primaryColor?.lch,
           let lower = outfit.bottom?.primaryColor?.lch,
           upper.neutrality != .neutral, lower.neutrality != .neutral,
           abs(upper.L - lower.L) < 0.06,
           OKLCH.hueDistance(upper.h, lower.h) > 30 {
            score -= 0.1
        }
        return min(max(score, 0), 1)
    }

    static func huePairScore(_ a: OKLCH, _ b: OKLCH) -> Double {
        let d = OKLCH.hueDistance(a.h, b.h)
        let loud = a.C > 0.13 && b.C > 0.13
        if d < 30 { return 0.9 }
        if d < 60 { return 0.75 }         // analogous
        if d < 135 { return loud ? 0.3 : 0.5 } // discordant
        return loud ? 0.5 : 0.8           // complementary: great when at least one side is muted
    }

    /// One bold pattern is plenty; two can work only if they share a color.
    public static func patternBalance(_ core: [Item]) -> Double {
        let bold = core.filter { $0.pattern.isBold }
        switch bold.count {
        case 0, 1:
            return 1
        case 2:
            let shareColor = bold[0].significantColors.contains { a in
                bold[1].significantColors.contains { b in a.lab.distance(to: b.lab) < 0.08 }
            }
            return shareColor ? 0.7 : 0.4
        default:
            return 0.1
        }
    }

    public static func formalityCohesion(_ core: [Item]) -> Double {
        let f = core.map(\.formality)
        guard let lo = f.min(), let hi = f.max() else { return 1 }
        switch hi - lo {
        case 0: return 1
        case 1: return 0.9
        case 2: return 0.55
        case 3: return 0.15
        default: return 0
        }
    }

    public static func occasionFit(_ core: [Item], occasion: Occasion) -> Double {
        guard !core.isEmpty else { return 0 }
        let mean = Double(core.map(\.formality).reduce(0, +)) / Double(core.count)
        return max(0, 1 - abs(mean - occasion.targetFormality) / 2)
    }

    public static func weatherFit(_ outfit: Outfit, weather: Weather) -> Double {
        let target = weather.upperWarmthTarget
        let warmth = Rules.upperWarmth(of: outfit)
        let distance = warmth < target.lowerBound
            ? target.lowerBound - warmth
            : max(0, warmth - target.upperBound)
        var score = distance == 0 ? 1 : (distance == 1 ? 0.6 : 0.2)
        if weather.isRainy {
            let covered = [outfit.shoes, outfit.outerwear].contains { $0?.waterResistant == true }
            if !covered { score *= 0.75 }
        }
        return score
    }

    /// Balanced silhouettes (one loose piece, one fitted) read as intentional.
    public static func fitBalance(_ outfit: Outfit) -> Double {
        guard let top = outfit.top, let bottom = outfit.bottom else { return 1 }
        if top.fit.isLoose && bottom.fit.isLoose {
            if top.fit == .oversized && bottom.fit == .oversized {
                let bothStreet = top.styleTags.contains(.street) && bottom.styleTags.contains(.street)
                return bothStreet ? 0.85 : 0.4
            }
            return 0.55
        }
        if top.fit == .slim && bottom.fit == .slim { return 0.85 }
        if top.fit == .regular && bottom.fit == .regular { return 0.95 }
        return 1
    }

    public static func statementBudget(_ core: [Item]) -> Double {
        switch core.filter(\.isStatement).count {
        case 0: return 0.9
        case 1: return 1
        case 2: return 0.4
        default: return 0.1
        }
    }

    /// Prefers items that haven't been worn in the last few days.
    public static func novelty(_ core: [Item], on date: Date) -> Double {
        guard !core.isEmpty else { return 1 }
        let values = core.map { item -> Double in
            guard let worn = item.lastWorn else { return 1 }
            let days = date.timeIntervalSince(worn) / 86_400
            if days < 2 { return 0.2 }
            if days < 7 { return 0.6 }
            return 1
        }
        return values.reduce(0, +) / Double(values.count)
    }
}
