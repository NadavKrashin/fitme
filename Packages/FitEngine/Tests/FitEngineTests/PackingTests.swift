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

struct StatementRotationTests {
    /// A red-trousers capsule worn to every meeting reads as "the same outfit again". Statement pieces rotate like
    /// tops.
    @Test func statementPiecesAreWornAtMostOncePerLaundryCycle() {
        var trip = Fixtures.days(3, weather: Weather(feelsLikeC: 18), occasions: [.work])
        trip[2].occasions.append(.formal)
        let result = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip)

        #expect(result.uncovered.isEmpty, "\(result.summary)")
        let statementWears = result.assignments
            .compactMap(\.outfit)
            .flatMap { $0.outfit.items.filter(\.isStatement).map(\.id) }
        #expect(statementWears.count == Set(statementWears).count, "repeated statement pieces: \(statementWears)")
    }
}

struct PackingHistoryTests {
    private let trip: [TripDay] = {
        var trip = Fixtures.days(5, weather: Weather(feelsLikeC: 21), occasions: [.casual])
        trip[3].occasions.append(.date)
        return trip
    }()

    /// A shirt that came home unworn from three trips stays home when the closet has an equal alternative.
    @Test func itemsThatCameHomeUnwornStayHome() {
        let before = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip)
        #expect(before.items.contains(Fixtures.item("t16")))

        var options = PackingOptions()
        options.packedUnworn = ["t16": 3]
        let after = PackingOptimizer(options: options).pack(closet: Fixtures.closet, trip: trip)

        #expect(!after.items.contains(Fixtures.item("t16")))
        #expect(after.uncovered.isEmpty, "\(after.summary)")
    }

    @Test func unwornHistoryRaisesCost() {
        var options = PackingOptions()
        options.packedUnworn = ["t16": 3]
        let shirt = Fixtures.item("t16")
        #expect(isClose(options.cost(of: shirt), 2 * shirt.packingCost))
        #expect(isClose(options.cost(of: Fixtures.item("t15")), Fixtures.item("t15").packingCost))
    }

    @Test func planForTheOptimizersOwnCapsuleMatchesPacking() {
        let packed = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip)
        let replanned = PackingOptimizer().plan(packed: packed.items, trip: trip)
        #expect(replanned.assignments.map(\.outfit?.id) == packed.assignments.map(\.outfit?.id))
        #expect(replanned.outfitCount == packed.outfitCount)
    }

    /// After the user removes a piece, every day is replanned from what's left.
    @Test func planForAnEditedCapsuleOnlyUsesPackedItems() {
        let packed = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip).items
        let edited = packed.filter { $0.id != "t16" }
        let result = PackingOptimizer().plan(packed: edited, trip: trip)

        #expect(result.assignments.count == 6)
        for outfit in result.assignments.compactMap(\.outfit) {
            #expect(outfit.outfit.items.allSatisfy(edited.contains))
        }
    }

    @Test func carryOnPacksFewerShoesAndCoats() {
        let trip = Fixtures.days(5, weather: Weather(feelsLikeC: 12), occasions: [.casual])
            + Fixtures.days(2, weather: Weather(feelsLikeC: 12), occasions: [.formal], from: 5)
        let result = PackingOptimizer(options: .carryOn).pack(closet: Fixtures.closet, trip: trip)
        #expect(result.items.count(where: { $0.category == .shoes }) <= 2)
        #expect(result.items.count(where: { $0.category == .outerwear }) <= 1)
    }
}
