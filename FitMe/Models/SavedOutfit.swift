import FitEngine
import Foundation
import SwiftData

/// An outfit the user liked, kept so they can come back to it.
@Model
final class SavedOutfit {
    /// The engine's outfit id (its item ids joined), so the same outfit is never saved twice.
    @Attribute(.unique) var outfitID: String
    var itemIDs: [String]
    /// Raw `Occasion` value; stored as a string so it can be filtered on (SwiftData can't predicate on enums).
    var occasionRaw: String
    var savedAt: Date

    init(outfit: Outfit, occasion: Occasion, savedAt: Date = .now) {
        outfitID = outfit.id
        itemIDs = outfit.items.map(\.id)
        occasionRaw = occasion.rawValue
        self.savedAt = savedAt
    }

    var occasion: Occasion? {
        Occasion(rawValue: occasionRaw)
    }
}
