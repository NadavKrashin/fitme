import FitEngine
import Foundation
import Testing
@testable import FitMe

struct TripPlannerTests {
    let closet = try! DemoCloset.items()
    let planner = TripPlanner()

    private func packed(_ details: TripDetails = TripFixtures.trip()) async -> TripDetails {
        await planner.pack(details, closet: closet, profile: StyleProfile())
    }

    @Test func packsEveryPlanWithOutfitsFromTheBag() async {
        let details = await packed()

        #expect(!details.packedItemIDs.isEmpty)
        #expect(details.packedItemIDs.count < closet.count / 2, "packs a capsule, not the closet")
        #expect(details.outfits.count == details.days.flatMap(\.occasions).count)
        #expect(details.outfits.allSatisfy { $0.isCovered })
        let bag = Set(details.packedItemIDs)
        #expect(details.outfits.allSatisfy { $0.itemIDs.allSatisfy(bag.contains) })
        #expect(details.outfitCount >= details.outfits.count)
    }

    @Test func laundryInTheWashTodayCanStillBePacked() async {
        let washing = closet.map { item in
            var item = item
            item.isAvailable = false
            return item
        }
        let details = await planner.pack(TripFixtures.trip(), closet: washing, profile: StyleProfile())
        #expect(!details.packedItemIDs.isEmpty)
    }

    @Test func replanningAfterLeavingSomethingOutKeepsWornOutfits() async throws {
        var details = await packed()
        details.outfits[0].wornOn = TripFixtures.day(1)
        let worn = details.outfits[0]
        let left = try #require(details.packedItemIDs.first { !worn.itemIDs.contains($0) })
        details.checkedOff = [left, details.packedItemIDs[0], "Socks"]

        let replanned = await planner.replan(
            details,
            packedIDs: details.packedItemIDs.filter { $0 != left },
            closet: closet,
            profile: StyleProfile()
        )

        #expect(!replanned.packedItemIDs.contains(left))
        #expect(replanned.outfits[0] == worn)
        #expect(replanned.outfits.dropFirst().allSatisfy { !$0.itemIDs.contains(left) })
        #expect(!replanned.checkedOff.contains(left))
        #expect(replanned.checkedOff.contains("Socks"))
    }

    @Test func alternativesComeFromTheBagAndDifferFromThePlan() async throws {
        let details = await packed(TripFixtures.trip(nights: 5))
        let planned = try #require(details.outfits.first { $0.occasion == .casual })

        let alternatives = planner.alternatives(to: planned, in: details, closet: closet, profile: StyleProfile())

        #expect(!alternatives.isEmpty)
        #expect(alternatives.count <= TripPlanner.swapLimit)
        let bag = Set(details.packedItemIDs)
        for alternative in alternatives {
            #expect(alternative.outfit.items.allSatisfy { bag.contains($0.id) })
            #expect(Set(alternative.outfit.items.map(\.id)) != Set(planned.itemIDs))
        }
    }

    @Test func carryOnMeansAtMostTwoPairsOfShoes() async {
        var trip = TripFixtures.trip(nights: 6)
        trip.luggage = .carryOn
        trip.days[3].occasions = [.formal]
        trip.days[4].occasions = [.sport]
        let details = await packed(trip)
        let shoes = closet.filter { details.packedItemIDs.contains($0.id) && $0.category == .shoes }
        #expect(shoes.count <= 2)
    }

    @Test func countsPiecesThatCameHomeUnworn() {
        var first = TripFixtures.trip()
        first.packedItemIDs = ["a", "b", "c"]
        first.debrief = TripDebrief(wornItemIDs: ["a"], completedAt: TripFixtures.now)
        var second = first
        second.debrief = TripDebrief(wornItemIDs: ["a", "b"], completedAt: TripFixtures.now)
        var undebriefed = first
        undebriefed.debrief = nil

        #expect(TripPlanner.packedUnworn(from: [first, second, undebriefed]) == ["b": 1, "c": 2])
    }

    @Test func flagsATopWornAgainBeforeTheWash() {
        let tops = closet.filter { $0.category == .top }
        var details = TripFixtures.trip(nights: 4)
        details.outfits = details.days.indices.map { day in
            PlannedOutfit(dayIndex: day, occasion: .casual, itemIDs: [tops[day == 3 ? 0 : day].id])
        }

        let marked = TripPlanner.markingRepeats(in: details, items: closet)
        #expect(marked.outfits.map(\.repeatsAPiece) == [false, false, false, true, false])

        details.laundry = .everyThreeDays // day 4 starts a fresh cycle
        #expect(TripPlanner.markingRepeats(in: details, items: closet).outfits.allSatisfy { !$0.repeatsAPiece })
    }
}
