import FitEngine
import SwiftData
import Testing
@testable import FitMe

/// Tests run in the Debug configuration, which includes the staging-only demo closet.
@MainActor
struct DemoClosetTests {
    @Test func everyOccasionHasSuggestions() throws {
        let items = try DemoCloset.items()
        #expect(items.count >= 50)
        #expect(Set(items.map(\.id)).count == items.count, "ids must be unique")

        let generator = OutfitGenerator()
        for occasion in Occasion.allCases {
            let outfits = generator.suggest(from: items, context: OutfitContext(occasion: occasion))
            #expect(!outfits.isEmpty, "no \(occasion) outfits")
        }
    }

    @Test func loadReplacesTheClosetAndClearEmptiesIt() throws {
        let container = try ModelContainer(
            for: ItemRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(ItemRecord(item: Item(
            id: "mine",
            name: "Mine",
            category: .top,
            colors: [],
            formality: 2,
            warmth: 1
        )))

        try DemoCloset.load(into: context)
        let loaded = try context.fetch(FetchDescriptor<ItemRecord>())
        #expect(try loaded.count == (DemoCloset.items().count))
        #expect(!loaded.contains { $0.itemID == "mine" })

        try DemoCloset.clear(context)
        #expect(try context.fetchCount(FetchDescriptor<ItemRecord>()) == 0)
    }
}
