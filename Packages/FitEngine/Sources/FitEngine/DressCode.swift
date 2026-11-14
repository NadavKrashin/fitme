import Foundation

/// Dress codes, after menswear dress-code guides. Formal (cocktail to business formal) is a dress shirt, tailored
/// trousers, a tailored jacket and dress shoes. Work is business casual: collared shirts and fine knits, chinos, wool
/// trousers or dark denim, leather shoes. Smart casual and dates are a step down, without gym or hiking gear.
extension Rules {
    /// Whether a piece belongs in the occasion's dress code at all.
    static func suitsDressCode(_ item: Item, occasion: Occasion) -> Bool {
        let isGear = !item.styleTags.isDisjoint(with: [.sporty, .outdoor])
        let isCore = [ItemCategory.top, .bottom, .onePiece, .shoes].contains(item.category)
        switch occasion {
        case .formal:
            return item.category == .outerwear || item.formality >= 4
        case .work:
            guard !(isCore && isGear) else { return false }
            switch item.category {
            case .top: return item.formality >= 2 && item.pattern != .graphic && !item.isStatement
            case .bottom: return !isShorts(item) && !isLightDenim(item)
            case .shoes: return item.formality >= 2
            default: return true
            }
        case .smartCasual, .date:
            return !(isCore && isGear) && !(item.category == .top && item.pattern == .graphic)
        case .casual, .sport, .beach, .travel:
            return true
        }
    }

    /// What a whole outfit needs beyond its pieces: formal wears a tailored jacket, and a suit jacket only goes with
    /// its own trousers.
    static func dressCodeViolations(of outfit: Outfit, occasion: Occasion, partial: Bool) -> [Violation] {
        var result: [Violation] = []
        if let jacket = outfit.midLayer, jacket.isSuitPiece, let trousers = outfit.bottom,
           !(trousers.isSuitPiece && sameColor(jacket, trousers)) {
            result.append(.splitSuit)
        }
        if !partial, occasion == .formal, outfit.onePiece == nil, (outfit.midLayer?.formality ?? 0) < 4 {
            result.append(.occasionMismatch)
        }
        return result
    }

    /// The tailored jacket a formal outfit wears whatever the weather; it isn't there for warmth.
    static func dressCodeJacket(in outfit: Outfit, occasion: Occasion) -> Item? {
        occasion == .formal ? outfit.midLayer.flatMap { $0.formality >= 4 ? $0 : nil } : nil
    }

    /// Shorts: light-weight bottoms.
    static func isShorts(_ item: Item) -> Bool {
        item.category == .bottom && item.warmth <= 1
    }

    /// Light- and mid-wash jeans: casual denim that business casual leaves out (dark denim passes).
    public static func isLightDenim(_ item: Item) -> Bool {
        guard item.category == .bottom, let color = item.primaryColor else { return false }
        return [StyleColor.denim, .lightBlue].contains(StyleColor(color.lch))
    }

    private static func sameColor(_ a: Item, _ b: Item) -> Bool {
        guard let first = a.primaryColor, let second = b.primaryColor else { return false }
        return StyleColor(first.lch) == StyleColor(second.lch)
    }
}
