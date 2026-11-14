import FitEngine
import Foundation
import SwiftData

/// An outfit logged with "Wear this", so the day's outfit can be shown, taken back, and looked back on.
@Model
final class WearEntry {
    /// The engine's outfit id, to tell whether a suggestion is already today's outfit.
    var outfitID: String
    var itemIDs: [String]
    /// Raw `Occasion` value; stored as a string so it can be filtered on (SwiftData can't predicate on enums).
    var occasionRaw: String?
    var wornOn: Date
    /// Each piece's `lastWorn` before this wear, as JSON, so taking it back restores the date.
    private var previousLastWornData: Data

    init(outfit: Outfit, occasion: Occasion?, wornOn: Date, previousLastWorn: [String: Date]) {
        outfitID = outfit.id
        itemIDs = outfit.items.map(\.id)
        occasionRaw = occasion?.rawValue
        self.wornOn = wornOn
        previousLastWornData = (try? JSONEncoder().encode(previousLastWorn)) ?? Data()
    }

    var occasion: Occasion? {
        occasionRaw.flatMap(Occasion.init(rawValue:))
    }

    /// Item id → when it was last worn before this entry; absent if it had never been worn.
    var previousLastWorn: [String: Date] {
        (try? JSONDecoder().decode([String: Date].self, from: previousLastWornData)) ?? [:]
    }
}
