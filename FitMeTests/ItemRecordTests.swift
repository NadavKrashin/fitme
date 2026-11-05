import FitEngine
import Foundation
import Testing
@testable import FitMe

struct ItemRecordTests {
    @Test func roundTripsEveryField() throws {
        let item = Item(
            id: "x1",
            name: "Breton tee",
            category: .top,
            subcategory: "t-shirt",
            colors: [ItemColor(hex: "#F2F0EA", proportion: 0.6), ItemColor(hex: "#1F2A44", proportion: 0.4)],
            pattern: .stripe,
            formality: 2,
            warmth: 1,
            fit: .slim,
            isStatement: true,
            styleTags: [.classic, .preppy],
            waterResistant: true,
            isAvailable: false,
            wearCount: 7,
            lastWorn: Date(timeIntervalSince1970: 1_790_000_000)
        )

        // Item's == compares ids only, so compare the full encoded form.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let roundTripped = ItemRecord(item: item).item
        #expect(try encoder.encode(roundTripped) == encoder.encode(item))
    }
}
