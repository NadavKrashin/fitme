import FitEngine
import Foundation
import SwiftData
import Testing
@testable import FitMe

@MainActor
struct FeedbackRecorderTests {
    let container = try! Persistence.makeInMemoryContainer()

    private func outfit(_ ids: [String]) throws -> Outfit {
        let items = try DemoCloset.items()
        return Outfit(items: ids.compactMap { id in items.first { $0.id == id } })
    }

    @Test func woreItUpdatesWearHistory() throws {
        let worn = try outfit(["t07", "b04", "s03"])
        for item in worn.items {
            container.mainContext.insert(ItemRecord(item: item))
        }
        let day = Date(timeIntervalSince1970: 1_790_000_000)

        FeedbackRecorder(context: container.mainContext).wear(worn, occasion: .date, on: day)

        let records = try container.mainContext.fetch(FetchDescriptor<ItemRecord>())
        #expect(records.count == 3)
        #expect(records.allSatisfy { $0.wearCount == 1 && $0.lastWorn == day })
        let entries = try container.mainContext.fetch(FetchDescriptor<WearEntry>())
        #expect(entries.map(\.outfitID) == [worn.id])
        #expect(entries.first?.occasion == .date)
    }

    /// Taking a wear back restores each piece's earlier wear date, unless it was worn again since.
    @Test func unwearRestoresTheEarlierWear() throws {
        let worn = try outfit(["t07", "b04", "s03"])
        let earlier = Date(timeIntervalSince1970: 1_780_000_000)
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        for item in worn.items {
            let record = ItemRecord(item: item)
            (record.wearCount, record.lastWorn) = (2, earlier)
            container.mainContext.insert(record)
        }
        let recorder = FeedbackRecorder(context: container.mainContext)

        let entry = recorder.wear(worn, occasion: nil, on: day)
        recorder.unwear(entry)

        let records = try container.mainContext.fetch(FetchDescriptor<ItemRecord>())
        #expect(records.allSatisfy { $0.wearCount == 2 && $0.lastWorn == earlier })
        #expect(try container.mainContext.fetchCount(FetchDescriptor<WearEntry>()) == 0)
    }

    @Test func likesPersistInTheProfile() throws {
        let liked = try outfit(["t05", "b04", "s01"])
        let recorder = FeedbackRecorder(context: container.mainContext)
        #expect(recorder.profile().affinityScore(liked.coreItems) == 0.5)

        recorder.record(.liked, for: liked)

        let stored = try container.mainContext.fetch(FetchDescriptor<StyleProfileRecord>())
        #expect(stored.count == 1)
        #expect(recorder.profile().affinityScore(liked.coreItems) > 0.5)
    }

    @Test func savedOutfitsAreUniqueAndRemovable() throws {
        let outfit = try outfit(["t13", "b04", "s03"])
        let recorder = FeedbackRecorder(context: container.mainContext)

        recorder.saveOutfit(outfit, occasion: .date)
        recorder.saveOutfit(outfit, occasion: .date)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SavedOutfit>()) == 1)

        recorder.removeSavedOutfit(id: outfit.id)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SavedOutfit>()) == 0)
    }
}
