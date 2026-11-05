import Testing
@testable import FitEngine

struct PackingTests {
    @Test func fiveDayCityBreak() {
        var trip = Fixtures.days(5, weather: Weather(feelsLikeC: 21), occasions: [.casual])
        trip[3].occasions.append(.date)
        let result = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip)

        #expect(result.uncovered.isEmpty, "\(result.summary)")
        #expect(result.items.count <= 12, "\(result.summary)")
        #expect(result.items.count(where: { $0.category == .shoes }) <= 3)
        #expect(result.outfitCount >= 6)
        expectNoTopRepeats(result)
    }

    @Test func tenDayTwoClimateTripWithLaundry() {
        let trip = Fixtures.days(5, weather: Weather(feelsLikeC: 29), occasions: [.casual])
            + Fixtures.days(5, weather: Weather(feelsLikeC: 7, precipitationChance: 0.6), occasions: [.casual], from: 5)
        var options = PackingOptions()
        options.laundryEveryNDays = 5
        let result = PackingOptimizer(options: options).pack(closet: Fixtures.closet, trip: trip)

        #expect(result.uncovered.isEmpty, "\(result.summary)")
        #expect(result.items.contains { $0.category == .outerwear && $0.warmth >= 4 }, "needs a warm coat")
        #expect(result.items.count(where: { $0.category == .shoes }) <= options.maxShoes)
        #expect(result.items.count(where: { $0.category == .outerwear }) <= options.maxOuterwear)
        for assignment in result.assignments where assignment.dayIndex >= 5 {
            let context = Fixtures.context(.casual, trip[assignment.dayIndex].weather)
            #expect(assignment.outfit.map { Rules.isValid($0.outfit, context: context) } == true)
        }
    }

    @Test func eventTripCoversFormalDinner() throws {
        var trip = Fixtures.days(3, weather: Weather(feelsLikeC: 18), occasions: [.work])
        trip[2].occasions.append(.formal)
        let result = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip)

        #expect(result.uncovered.isEmpty, "\(result.summary)")
        let dinner = try #require(result.assignments.first { $0.occasion == .formal }?.outfit)
        #expect((dinner.outfit.shoes?.formality ?? 0) >= 4)
    }

    @Test func packingIsDeterministic() {
        let trip = Fixtures.days(4, weather: Weather(feelsLikeC: 15), occasions: [.casual, .smartCasual])
        let a = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip)
        let b = PackingOptimizer().pack(closet: Fixtures.closet.reversed(), trip: trip)
        #expect(a.items.map(\.id) == b.items.map(\.id))
        #expect(a.assignments.map(\.outfit?.id) == b.assignments.map(\.outfit?.id))
    }

    @Test func essentialsChecklist() {
        let list = Essentials.checklist(days: 10, laundryEveryNDays: 4, occasions: [.beach])
        #expect(list.first { $0.name == "Underwear" }?.count == 5)
        #expect(list.contains { $0.name == "Swimwear" })
    }

    private func expectNoTopRepeats(_ result: PackingResult, sourceLocation: SourceLocation = #_sourceLocation) {
        let bases = result.assignments.compactMap { $0.outfit?.outfit.baseKey }
        #expect(
            bases.count == Set(bases).count,
            "a top was planned twice without laundry",
            sourceLocation: sourceLocation
        )
        #expect(!result.assignments.contains { $0.exceedsWearLimit }, sourceLocation: sourceLocation)
    }
}
