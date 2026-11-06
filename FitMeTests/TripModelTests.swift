import FitEngine
import Foundation
import SwiftData
import Testing
@testable import FitMe

@MainActor
struct TripModelTests {
    let closet = try! DemoCloset.items()
    let container = try! Persistence.makeInMemoryContainer()

    private func model(reviewer: FakeCapsuleReviewer = .init()) async -> TripModel {
        let details = await TripPlanner().pack(TripFixtures.trip(), closet: closet, profile: StyleProfile())
        let record = TripRecord(details: details)
        container.mainContext.insert(record)
        return TripModel(record: record, planner: TripPlanner(), reviewer: reviewer, context: container.mainContext)
    }

    @Test func tickingOffIsStored() async {
        let model = await model()
        let first = model.details.packedItemIDs[0]

        model.toggleChecked(first)
        #expect(model.isChecked(first))
        #expect(model.record.details.checkedOff == [first])

        model.toggleChecked(first)
        #expect(!model.isChecked(first))
    }

    @Test func leavingSomethingOutReplansAndCanBeUndone() async throws {
        let model = await model()
        let before = model.details
        let item = try #require(closet.first { $0.id == before.packedItemIDs[0] })

        await model.leaveOut(item, closet: closet)

        #expect(!model.details.packedItemIDs.contains(item.id))
        #expect(model.details.outfits.allSatisfy { !$0.itemIDs.contains(item.id) })
        let undo = try #require(model.toast?.undo)
        undo()
        #expect(model.details == before)
        #expect(model.record.details == before)
    }

    @Test func bringingAnItemPacksIt() async throws {
        let model = await model()
        let extra = try #require(closet.first { $0.category == .top && !model.details.packedItemIDs.contains($0.id) })

        await model.bring(extra, closet: closet)

        #expect(model.details.packedItemIDs.contains(extra.id))
        #expect(model.toast?.message.contains(extra.name.lowercased()) == true)
    }

    @Test func swappingReplacesOnePlannedOutfit() async throws {
        let model = await model()
        let alternative = try #require(model.alternatives(to: 1, closet: closet).first)

        model.swap(1, to: alternative.outfit, closet: closet)

        #expect(Set(model.details.outfits[1].itemIDs) == Set(alternative.outfit.items.map(\.id)))
    }

    @Test func wearingLogsTheOutfitOnce() async throws {
        let model = await model()
        let itemsByID = Dictionary(uniqueKeysWithValues: closet.map { ($0.id, $0) })
        for item in closet {
            container.mainContext.insert(ItemRecord(item: item))
        }

        model.wear(0, itemsByID: itemsByID, on: TripFixtures.day(1))
        model.wear(0, itemsByID: itemsByID, on: TripFixtures.day(1))

        #expect(model.details.outfits[0].wornOn == TripFixtures.day(1))
        let wornID = model.details.outfits[0].itemIDs[0]
        let record = try #require(try container.mainContext.fetch(FetchDescriptor<ItemRecord>())
            .first { $0.itemID == wornID })
        #expect(record.wearCount == 1)
        #expect(model.details.plannedWornItemIDs == Set(model.details.outfits[0].itemIDs))
    }

    @Test func applyingASuggestionChangesTheBagAndClearsIt() async throws {
        let model = await model()
        await model.askForReview(closet: closet)
        guard case let .reviewed(review) = model.review else {
            Issue.record("expected a review")
            return
        }
        let change = try #require(review.changes.first)

        await model.apply(change, closet: closet)

        #expect(try !model.details.packedItemIDs.contains(#require(change.leaveOut)))
        #expect(model.review == .reviewed(CapsuleReview(verdict: review.verdict, changes: [])))
    }

    @Test func reviewErrorsBecomeAMessage() async {
        let model = await model(reviewer: FakeCapsuleReviewer(error: ClaudeError.missingAPIKey))
        await model.askForReview(closet: closet)
        #expect(model.review == .failed(ClaudeError.missingAPIKey.userMessage))
    }

    @Test func debriefOnlyCountsPackedPieces() async {
        let model = await model()
        let packed = model.details.packedItemIDs
        model.saveDebrief(wornItemIDs: Set(packed.prefix(packed.count - 1)).union(["not-packed"]))

        #expect(model.details.debrief?.wornItemIDs.contains("not-packed") == false)
        #expect(model.wornShare == Double(packed.count - 1) / Double(packed.count))
        #expect(model.details.packedUnwornItemIDs == [packed[packed.count - 1]])
    }
}
