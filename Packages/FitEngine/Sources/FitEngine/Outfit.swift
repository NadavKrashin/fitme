import Foundation

/// A set of items worn together, ordered outermost-first (the order a flat-lay collage stacks them).
public struct Outfit: Identifiable, Hashable {
    public let items: [Item]

    public init(items: [Item]) {
        let order = ItemCategory.allCases
        self.items = items.sorted {
            let a = order.firstIndex(of: $0.category)!, b = order.firstIndex(of: $1.category)!
            return a != b ? a < b : $0.id < $1.id
        }
    }

    public var id: String { items.map(\.id).joined(separator: "+") }

    public func item(in category: ItemCategory) -> Item? { items.first { $0.category == category } }
    public func items(in category: ItemCategory) -> [Item] { items.filter { $0.category == category } }

    public var top: Item? { item(in: .top) }
    public var bottom: Item? { item(in: .bottom) }
    public var onePiece: Item? { item(in: .onePiece) }
    public var midLayer: Item? { item(in: .midLayer) }
    public var outerwear: Item? { item(in: .outerwear) }
    public var shoes: Item? { item(in: .shoes) }

    public var coreItems: [Item] { items.filter { $0.category.isCore } }

    /// The piece that makes an outfit feel "different" from another: its top, or its one-piece.
    public var baseKey: String { (onePiece ?? top)?.id ?? id }

    public func contains(_ item: Item) -> Bool { items.contains(item) }
}

public struct ScoredOutfit: Identifiable, Hashable {
    public let outfit: Outfit
    public let breakdown: ScoreBreakdown

    public var id: String { outfit.id }
    public var score: Double { breakdown.total }

    public static func == (lhs: ScoredOutfit, rhs: ScoredOutfit) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
