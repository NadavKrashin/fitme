import Foundation

public struct ScoreWeights: Equatable, Sendable {
    public var color = 0.28
    public var pattern = 0.12
    public var formality = 0.15
    public var occasion = 0.12
    public var weather = 0.13
    public var shoes = 0.12
    public var fit = 0.06
    public var statement = 0.06
    public var novelty = 0.03
    /// Most points your reactions can add to or take from the 0...100 total. Added on top of the blend, so an
    /// outfit scores the same with no profile as with a profile that has no opinion about it. Near either end of
    /// the scale the room left is the limit, so a liked outfit still outranks a near-copy instead of tying at 100.
    public var learnedPoints = 8.0

    public init() {}
}

/// Each component is 0...1; `total` is the weighted blend on a 0...100 scale, moved by what was learned (`affinity`,
/// where 0.5 is neutral).
public struct ScoreBreakdown: Equatable, Sendable {
    public var color: Double
    public var pattern: Double
    public var formality: Double
    public var occasion: Double
    public var weather: Double
    public var shoes: Double
    public var fit: Double
    public var statement: Double
    public var affinity: Double
    public var novelty: Double
    public var total: Double
}

/// Soft styling judgement: how good an outfit looks, assuming it already passed `Rules`.
public struct OutfitScorer: Sendable {
    public var weights: ScoreWeights

    public init(weights: ScoreWeights = ScoreWeights()) {
        self.weights = weights
    }

    /// `partial` scores an outfit still being assembled, so weather is left neutral.
    public func score(_ outfit: Outfit, context: OutfitContext, partial: Bool = false) -> ScoreBreakdown {
        let core = outfit.coreItems
        let w = weights
        var b = ScoreBreakdown(
            color: Self.colorHarmony(outfit, palette: context.palette),
            pattern: Self.patternBalance(core),
            formality: Self.formalityCohesion(core),
            occasion: Self.occasionFit(core, occasion: context.occasion),
            weather: partial ? 1 : Self.weatherFit(outfit, weather: context.weather),
            shoes: Self.shoePairing(outfit, occasion: context.occasion),
            fit: Self.fitBalance(outfit),
            statement: Self.statementBudget(core),
            affinity: context.profile?.affinityScore(core) ?? 0.5,
            novelty: Self.novelty(core, on: context.date),
            total: 0
        )
        let weighted = w.color * b.color + w.pattern * b.pattern + w.formality * b.formality
            + w.occasion * b.occasion + w.weather * b.weather + w.shoes * b.shoes + w.fit * b.fit
            + w.statement * b.statement + w.novelty * b.novelty
        let sum = w.color + w.pattern + w.formality + w.occasion + w.weather + w.shoes + w.fit + w.statement
            + w.novelty
        let blend = weighted / sum * 100
        let opinion = 2 * b.affinity - 1
        b.total = blend + opinion * min(w.learnedPoints, opinion > 0 ? 100 - blend : blend)
        return b
    }

    // MARK: Components

    /// Color, after menswear color guides: outfits are built on neutrals (black, grey, white, navy, denim, beige,
    /// brown, camel, khaki, olive). An accent color is a choice, not a requirement, and several accents must relate
    /// by hue. About three colors read as deliberate; more looks busy. `palette` is how much color the user is in the
    /// mood for.
    public static func colorHarmony(_ outfit: Outfit, palette: Palette = .balanced) -> Double {
        let colors = outfit.coreItems.flatMap(\.significantColors)
        var score = accentScore(accentFamilies(colors.map(\.lch)), palette: palette)
        score -= 0.05 * Double(max(0, Set(colors.map(\.family)).count - 3))
        if isMuddy(outfit) {
            score -= 0.1
        }
        return min(max(score, 0), 1)
    }

    /// Chromatic colors grouped by hue: within ~25° they read as one family (tonal dressing).
    static func accentFamilies(_ colors: [OKLCH]) -> [OKLCH] {
        var families: [OKLCH] = []
        for color in colors where color.neutrality == .chromatic {
            if !families.contains(where: { OKLCH.hueDistance($0.h, color.h) <= 25 }) {
                families.append(color)
            }
        }
        return families
    }

    static func accentScore(_ accents: [OKLCH], palette: Palette) -> Double {
        guard accents.count > 1 else {
            switch (palette, accents.first) {
            case (.colorful, nil): return 0.8
            case (_, nil), (.colorful, _): return 1
            case (.balanced, _): return 0.95
            case let (.neutral, accent?): return accent.C < 0.13 ? 0.75 : 0.6
            }
        }
        var pairs: [Double] = []
        for i in 0 ..< accents.count {
            for j in (i + 1) ..< accents.count {
                pairs.append(huePairScore(accents[i], accents[j]))
            }
        }
        let harmony = pairs.reduce(0, +) / Double(pairs.count) - 0.12 * Double(accents.count - 2)
        switch palette {
        case .neutral: return harmony * 0.5
        case .balanced: return harmony
        case .colorful: return min(1, harmony + 0.05)
        }
    }

    /// Different hues at the same lightness between top and bottom look muddy.
    static func isMuddy(_ outfit: Outfit) -> Bool {
        guard let upper = (outfit.top ?? outfit.onePiece)?.primaryColor?.lch,
              let lower = outfit.bottom?.primaryColor?.lch,
              upper.neutrality != .neutral, lower.neutrality != .neutral
        else { return false }
        return abs(upper.L - lower.L) < 0.06 && OKLCH.hueDistance(upper.h, lower.h) > 30
    }

    static func huePairScore(_ a: OKLCH, _ b: OKLCH) -> Double {
        let d = OKLCH.hueDistance(a.h, b.h)
        let loud = a.C > 0.13 && b.C > 0.13
        if d < 30 {
            return 0.9
        }
        if d < 60 {
            return 0.75
        } // analogous
        if d < 135 {
            return loud ? 0.3 : 0.5
        } // discordant
        return loud ? 0.5 : 0.8 // complementary: great when at least one side is muted
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
            if !covered {
                score *= 0.75
            }
        }
        return score
    }

    /// How well the shoes suit the rest of the outfit, after menswear shoe-and-trouser guides: they should match its
    /// dress code, and their color should follow the trousers. 1 when there are no shoes yet.
    public static func shoePairing(_ outfit: Outfit, occasion: Occasion) -> Double {
        guard let shoes = outfit.shoes else { return 1 }
        let rest = outfit.coreItems.filter { $0.category != .shoes }
        guard !rest.isEmpty else { return 1 }
        let mean = Double(rest.map(\.formality).reduce(0, +)) / Double(rest.count)
        let dressCode = switch abs(Double(shoes.formality) - mean) {
        case ...0.75: 1.0
        case ...1.5: 0.85
        case ...2.5: 0.5
        default: 0.2
        }
        let tone = ShoeTone(shoes)
        var color = (outfit.bottom.map(TrouserTone.init)).map { tone.pairing(with: $0) } ?? 1
        if occasion == .formal, tone != .black {
            color *= 0.7
        }
        return dressCode * color
    }

    /// Balanced silhouettes (one loose piece, one fitted) read as intentional.
    public static func fitBalance(_ outfit: Outfit) -> Double {
        guard let top = outfit.top, let bottom = outfit.bottom else { return 1 }
        if top.fit.isLoose, bottom.fit.isLoose {
            if top.fit == .oversized, bottom.fit == .oversized {
                let bothStreet = top.styleTags.contains(.street) && bottom.styleTags.contains(.street)
                return bothStreet ? 0.85 : 0.4
            }
            return 0.55
        }
        if top.fit == .slim, bottom.fit == .slim {
            return 0.85
        }
        if top.fit == .regular, bottom.fit == .regular {
            return 0.95
        }
        return 1
    }

    public static func statementBudget(_ core: [Item]) -> Double {
        // One statement piece is fine; it just isn't a reason to prefer an outfit.
        switch core.filter(\.isStatement).count {
        case 0, 1: return 1
        case 2: return 0.4
        default: return 0.1
        }
    }

    /// Prefers items that haven't been worn in the last few days.
    public static func novelty(_ core: [Item], on date: Date) -> Double {
        guard !core.isEmpty else { return 1 }
        let values = core.map { item -> Double in
            guard let worn = item.lastWorn else { return 1 }
            let days = date.timeIntervalSince(worn) / 86400
            if days < 2 {
                return 0.2
            }
            if days < 7 {
                return 0.6
            }
            return 1
        }
        return values.reduce(0, +) / Double(values.count)
    }
}

/// Shoe colors as shoe guides group them.
enum ShoeTone: Equatable {
    case black, brown, light, navy, colorful

    init(_ shoes: Item) {
        switch shoes.primaryColor?.family {
        case .black, .charcoal: self = .black
        case .brown, .camel, .khaki, .beige, .olive, .red, .orange: self = .brown
        case .white, .grey, nil: self = .light
        case .navy, .denim: self = .navy
        default: self = .colorful
        }
    }

    /// How well these shoes go with trousers of a tone, 0...1.
    func pairing(with trousers: TrouserTone) -> Double {
        Self.pairings[self]?[trousers] ?? 0.85
    }

    /// Brown is the versatile choice (navy, grey, denim, earth tones); black belongs with black and charcoal and is
    /// contested with navy; brown shoes with black trousers is the classic miss; white sneakers suit denim best.
    private static let pairings: [ShoeTone: [TrouserTone: Double]] = [
        .black: [.dark: 1, .grey: 0.9, .denim: 0.9, .navy: 0.75, .earth: 0.55, .light: 0.8, .colorful: 0.8],
        .brown: [.dark: 0.5, .grey: 1, .navy: 1, .denim: 1, .earth: 1, .light: 1, .colorful: 0.9],
        .light: [.dark: 0.75, .grey: 0.9, .navy: 0.9, .denim: 1, .earth: 0.9, .light: 0.85, .colorful: 0.9],
        .navy: [.dark: 0.7, .grey: 0.85, .navy: 0.85, .denim: 0.85, .earth: 0.95, .light: 0.95, .colorful: 0.85],
        .colorful: [.dark: 0.85, .grey: 0.85, .navy: 0.85, .denim: 0.85, .earth: 0.85, .light: 0.85, .colorful: 0.7],
    ]
}

/// Trouser colors as shoe guides group them.
enum TrouserTone: Equatable {
    case dark, grey, navy, denim, earth, light, colorful

    init(_ trousers: Item) {
        guard let color = trousers.primaryColor else {
            self = .grey
            return
        }
        // Mid-grey wool reads as grey, not charcoal: only truly dark neutrals call for black shoes.
        if color.lch.neutrality == .neutral {
            self = color.lch.L < 0.42 ? .dark : (color.lch.L > 0.9 ? .light : .grey)
            return
        }
        switch color.family {
        case .navy: self = .navy
        case .denim, .blue: self = .denim
        case .beige, .brown, .camel, .khaki, .olive: self = .earth
        default: self = .colorful
        }
    }
}
