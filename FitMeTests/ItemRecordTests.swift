import FitEngine
import Foundation
import Testing
@testable import FitMe

struct ItemRecordTests {
    @Test func roundTripsEveryField() {
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

        let roundTripped = ItemRecord(item: item).item

        // Item's == compares ids only, so check every field. (Comparing JSON encodings is flaky: `styleTags` is a
        // Set, which encodes in arbitrary order.)
        #expect(roundTripped.id == item.id)
        #expect(roundTripped.name == item.name)
        #expect(roundTripped.category == item.category)
        #expect(roundTripped.subcategory == item.subcategory)
        #expect(roundTripped.colors == item.colors)
        #expect(roundTripped.pattern == item.pattern)
        #expect(roundTripped.formality == item.formality)
        #expect(roundTripped.warmth == item.warmth)
        #expect(roundTripped.fit == item.fit)
        #expect(roundTripped.isStatement == item.isStatement)
        #expect(roundTripped.styleTags == item.styleTags)
        #expect(roundTripped.waterResistant == item.waterResistant)
        #expect(roundTripped.isAvailable == item.isAvailable)
        #expect(roundTripped.wearCount == item.wearCount)
        #expect(roundTripped.lastWorn == item.lastWorn)
    }
}
