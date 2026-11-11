import FitEngine
import Foundation
import SwiftData
import Testing
@testable import FitMe

@MainActor
struct InsightsModelTests {
    let now = Date(timeIntervalSince1970: 1_793_966_400)
    let day: TimeInterval = 86400

    private func record(_ id: String, addedDaysAgo: Double, wornDaysAgo: Double?) -> ItemRecord {
        let item = Item(id: id, name: id, category: .top, colors: [ItemColor(hex: "#F5F5F2")], formality: 2, warmth: 1)
        let record = ItemRecord(item: item, addedAt: now.addingTimeInterval(-addedDaysAgo * day))
        record.lastWorn = wornDaysAgo.map { now.addingTimeInterval(-$0 * day) }
        return record
    }

    @Test func restingListsNeverWornThenLongestUnworn() {
        let records = [
            record("recent", addedDaysAgo: 100, wornDaysAgo: 3),
            record("long ago", addedDaysAgo: 200, wornDaysAgo: 150),
            record("a while", addedDaysAgo: 200, wornDaysAgo: 70),
            record("never", addedDaysAgo: 30, wornDaysAgo: nil),
            record("just bought", addedDaysAgo: 2, wornDaysAgo: nil),
        ]

        let resting = InsightsModel.resting(records, now: now, calendar: TripFixtures.calendar)

        #expect(resting.map(\.itemID) == ["never", "long ago", "a while"])
    }

    @Test func analyzesTheDemoCloset() async throws {
        let model = InsightsModel(analyzer: ClosetAnalyzer())

        try await model.analyze(DemoCloset.items())

        guard case let .analyzed(insights) = model.state else {
            Issue.record("expected an analysis, got \(model.state)")
            return
        }
        #expect(insights.totalLooks > 100)
        #expect(try insights.looksByItem.count == (DemoCloset.items().count))
    }

    @Test func forgettingWhatWasLearnedKeepsSavedOutfits() throws {
        let container = try Persistence.makeInMemoryContainer()
        let recorder = FeedbackRecorder(context: container.mainContext)
        let outfit = try Outfit(items: Array(DemoCloset.items().prefix(2)))
        recorder.record(.liked, for: outfit)
        recorder.saveOutfit(outfit, occasion: .casual)

        recorder.resetLearning()

        #expect(recorder.profile().isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SavedOutfit>()) == 1)
    }
}
