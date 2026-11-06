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

        FeedbackRecorder(context: container.mainContext).record(.wore, for: worn, on: day)

        let records = try container.mainContext.fetch(FetchDescriptor<ItemRecord>())
        #expect(records.count == 3)
        #expect(records.allSatisfy { $0.wearCount == 1 && $0.lastWorn == day })
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
}
