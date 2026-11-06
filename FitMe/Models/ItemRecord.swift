import FitEngine
import Foundation
import SwiftData

/// A closet item as stored on device. The styling engine never sees this type; it works on `Item` values.
@Model
final class ItemRecord {
    @Attribute(.unique) var itemID: String
    var name: String
    var category: ItemCategory
    var subcategory: String?
    var colors: [StoredColor]
    var pattern: ItemPattern
    var formality: Int
    var warmth: Int
    var fit: Fit
    var isStatement: Bool
    var styleTags: [StyleTag]
    var waterResistant: Bool
    var isAvailable: Bool
    var wearCount: Int
    var lastWorn: Date?
    var addedAt: Date

    /// Original photo (JPEG) and the item cut out on a transparent square (PNG). Stored outside the database file.
    @Attribute(.externalStorage) var photo: Data?
    @Attribute(.externalStorage) var cutout: Data?

    init(item: Item, photo: Data? = nil, cutout: Data? = nil, addedAt: Date = .now) {
        itemID = item.id
        name = item.name
        category = item.category
        subcategory = item.subcategory
        colors = item.colors.map(StoredColor.init)
        pattern = item.pattern
        formality = item.formality
        warmth = item.warmth
        fit = item.fit
        isStatement = item.isStatement
        styleTags = item.styleTags.sorted { $0.rawValue < $1.rawValue }
        waterResistant = item.waterResistant
        isAvailable = item.isAvailable
        wearCount = item.wearCount
        lastWorn = item.lastWorn
        self.photo = photo
        self.cutout = cutout
        self.addedAt = addedAt
    }

    /// Copies everything the user can edit. Identity, photos and wear history stay as they are.
    func update(from item: Item) {
        name = item.name
        category = item.category
        subcategory = item.subcategory
        colors = item.colors.map(StoredColor.init)
        pattern = item.pattern
        formality = item.formality
        warmth = item.warmth
        fit = item.fit
        isStatement = item.isStatement
        styleTags = item.styleTags.sorted { $0.rawValue < $1.rawValue }
        waterResistant = item.waterResistant
        isAvailable = item.isAvailable
    }

    var item: Item {
        Item(
            id: itemID,
            name: name,
            category: category,
            subcategory: subcategory,
            colors: colors.map { ItemColor(hex: $0.hex, proportion: $0.proportion) },
            pattern: pattern,
            formality: formality,
            warmth: warmth,
            fit: fit,
            isStatement: isStatement,
            styleTags: Set(styleTags),
            waterResistant: waterResistant,
            isAvailable: isAvailable,
            wearCount: wearCount,
            lastWorn: lastWorn
        )
    }
}

/// `ItemColor` minus its derived color-space values, which are recomputed from the hex on load.
struct StoredColor: Codable, Hashable {
    var hex: String
    var proportion: Double

    init(_ color: ItemColor) {
        hex = color.hex
        proportion = color.proportion
    }
}
