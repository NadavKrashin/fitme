import Foundation

public enum ItemCategory: String, Codable, CaseIterable, Sendable {
    case outerwear, midLayer, top, onePiece, bottom, shoes, bag, accessory

    /// Items that make up the outfit itself (bags and accessories are styled separately).
    public var isCore: Bool {
        self != .bag && self != .accessory
    }

    /// Outermost first: the order a flat-lay collage stacks pieces from top to bottom.
    public var layerOrder: Int {
        switch self {
        case .outerwear: 0
        case .midLayer: 1
        case .top: 2
        case .onePiece: 3
        case .bottom: 4
        case .shoes: 5
        case .bag: 6
        case .accessory: 7
        }
    }
}

public enum ItemPattern: String, Codable, CaseIterable, Sendable {
    case solid, textured, stripe, check, floral, graphic, print, other

    public var isBold: Bool {
        self != .solid && self != .textured
    }
}

public enum Fit: String, Codable, CaseIterable, Sendable {
    case slim, regular, relaxed, oversized

    public var isLoose: Bool {
        self == .relaxed || self == .oversized
    }
}

public enum StyleTag: String, Codable, CaseIterable, Sendable {
    case minimal, classic, street, sporty, preppy, boho, edgy, romantic, outdoor, swim
}

/// One color of an item, as measured from its photo.
public struct ItemColor: Codable, Hashable, Sendable {
    public let hex: String
    /// Share of the item's visible area, 0...1.
    public let proportion: Double
    public let lab: OKLab
    public let lch: OKLCH

    public init(hex: String, proportion: Double = 1) {
        self.hex = hex
        self.proportion = proportion
        lab = OKLab(RGB(hex: hex) ?? RGB(r: 0.5, g: 0.5, b: 0.5))
        lch = lab.lch
    }

    enum CodingKeys: String, CodingKey { case hex, proportion }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hex: c.decode(String.self, forKey: .hex),
            proportion: c.decodeIfPresent(Double.self, forKey: .proportion) ?? 1
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hex, forKey: .hex)
        try c.encode(proportion, forKey: .proportion)
    }
}

/// A piece of clothing in the closet.
public struct Item: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var category: ItemCategory
    public var subcategory: String?
    /// Dominant colors, largest share first.
    public var colors: [ItemColor]
    public var pattern: ItemPattern
    /// 1 = gym/lounge, 2 = casual, 3 = smart casual, 4 = dressy, 5 = black tie.
    public var formality: Int
    /// 1 = very light (tee, shorts, sandals) ... 5 = heavy (wool coat, puffer).
    public var warmth: Int
    public var fit: Fit
    public var isStatement: Bool
    public var styleTags: Set<StyleTag>
    public var waterResistant: Bool
    /// False while the item is in the laundry or otherwise unavailable.
    public var isAvailable: Bool
    public var wearCount: Int
    public var lastWorn: Date?

    public init(
        id: String,
        name: String,
        category: ItemCategory,
        subcategory: String? = nil,
        colors: [ItemColor],
        pattern: ItemPattern = .solid,
        formality: Int,
        warmth: Int,
        fit: Fit = .regular,
        isStatement: Bool = false,
        styleTags: Set<StyleTag> = [],
        waterResistant: Bool = false,
        isAvailable: Bool = true,
        wearCount: Int = 0,
        lastWorn: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.subcategory = subcategory
        self.colors = colors.sorted { $0.proportion > $1.proportion }
        self.pattern = pattern
        self.formality = formality
        self.warmth = warmth
        self.fit = fit
        self.isStatement = isStatement
        self.styleTags = styleTags
        self.waterResistant = waterResistant
        self.isAvailable = isAvailable
        self.wearCount = wearCount
        self.lastWorn = lastWorn
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, subcategory, colors, pattern, formality, warmth, fit
        case isStatement, styleTags, waterResistant, isAvailable, wearCount, lastWorn
    }

    /// Optional fields fall back to defaults so hand-written fixtures and AI tagging output stay short.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            name: c.decode(String.self, forKey: .name),
            category: c.decode(ItemCategory.self, forKey: .category),
            subcategory: c.decodeIfPresent(String.self, forKey: .subcategory),
            colors: c.decode([ItemColor].self, forKey: .colors),
            pattern: c.decodeIfPresent(ItemPattern.self, forKey: .pattern) ?? .solid,
            formality: c.decode(Int.self, forKey: .formality),
            warmth: c.decode(Int.self, forKey: .warmth),
            fit: c.decodeIfPresent(Fit.self, forKey: .fit) ?? .regular,
            isStatement: c.decodeIfPresent(Bool.self, forKey: .isStatement) ?? false,
            styleTags: c.decodeIfPresent(Set<StyleTag>.self, forKey: .styleTags) ?? [],
            waterResistant: c.decodeIfPresent(Bool.self, forKey: .waterResistant) ?? false,
            isAvailable: c.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? true,
            wearCount: c.decodeIfPresent(Int.self, forKey: .wearCount) ?? 0,
            lastWorn: c.decodeIfPresent(Date.self, forKey: .lastWorn)
        )
    }

    public static func == (lhs: Item, rhs: Item) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public var primaryColor: ItemColor? {
        colors.first
    }

    /// Colors large enough to read at a glance: the primary color plus any taking a quarter of the item or more.
    public var significantColors: [ItemColor] {
        colors.enumerated().filter { $0.offset == 0 || $0.element.proportion >= 0.25 }.map(\.element)
    }

    /// Relative suitcase space, used by the packing optimizer.
    public var packingCost: Double {
        switch category {
        case .top: return 1.0
        case .onePiece: return 1.3
        case .bottom, .midLayer: return 1.5
        case .outerwear: return warmth >= 4 ? 4.0 : 2.5
        case .shoes: return 3.0
        case .bag, .accessory: return 0.5
        }
    }
}
