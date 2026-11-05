import XCTest
@testable import FitEngine

final class PackingTests: XCTestCase {
    func testFiveDayCityBreak() {
        var trip = Fixtures.days(5, weather: Weather(feelsLikeC: 21), occasions: [.casual])
        trip[3].occasions.append(.date)
        let result = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip)
        print("City break:", result.summary, result.items.map(\.name))

        XCTAssertTrue(result.uncovered.isEmpty)
        XCTAssertLessThanOrEqual(result.items.count, 12)
        XCTAssertLessThanOrEqual(result.items.filter { $0.category == .shoes }.count, 3)
        XCTAssertGreaterThanOrEqual(result.outfitCount, 6)
        assertNoRepeatedTops(result)
    }

    func testTenDayTwoClimateTrip() {
        let trip = Fixtures.days(5, weather: Weather(feelsLikeC: 29), occasions: [.casual])
            + Fixtures.days(5, weather: Weather(feelsLikeC: 7, precipitationChance: 0.6), occasions: [.casual], from: 5)
        var options = PackingOptions()
        options.laundryEveryNDays = 5
        let result = PackingOptimizer(options: options).pack(closet: Fixtures.closet, trip: trip)
        print("Two climates:", result.summary, result.items.map(\.name))

        XCTAssertTrue(result.uncovered.isEmpty)
        XCTAssertTrue(result.items.contains { $0.category == .outerwear && $0.warmth >= 4 }, "needs a warm coat")
        XCTAssertLessThanOrEqual(result.items.filter { $0.category == .shoes }.count, 3)
        XCTAssertLessThanOrEqual(result.items.filter { $0.category == .outerwear }.count, 2)
        for a in result.assignments where a.dayIndex >= 5 {
            XCTAssertTrue(Rules.isValid(a.outfit!.outfit, context: OutfitContext(occasion: .casual, weather: trip[a.dayIndex].weather)))
        }
    }

    func testEventTripCoversFormalDinner() {
        var trip = Fixtures.days(3, weather: Weather(feelsLikeC: 18), occasions: [.work])
        trip[2].occasions.append(.formal)
        let result = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip)
        print("Event trip:", result.summary, result.items.map(\.name))

        XCTAssertTrue(result.uncovered.isEmpty)
        let dinner = result.assignments.first { $0.occasion == .formal }!.outfit!
        XCTAssertGreaterThanOrEqual(dinner.outfit.shoes!.formality, 4)
    }

    func testPackingIsDeterministic() {
        let trip = Fixtures.days(4, weather: Weather(feelsLikeC: 15), occasions: [.casual, .smartCasual])
        let a = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip)
        let b = PackingOptimizer().pack(closet: Fixtures.closet.reversed(), trip: trip)
        XCTAssertEqual(a.items.map(\.id), b.items.map(\.id))
        XCTAssertEqual(a.assignments.map { $0.outfit?.id }, b.assignments.map { $0.outfit?.id })
    }

    func testEssentialsChecklist() {
        let list = Essentials.checklist(days: 10, laundryEveryNDays: 4, occasions: [.beach])
        XCTAssertEqual(list.first { $0.name == "Underwear" }?.count, 5)
        XCTAssertTrue(list.contains { $0.name == "Swimwear" })
    }

    private func assertNoRepeatedTops(_ result: PackingResult, file: StaticString = #filePath, line: UInt = #line) {
        let bases = result.assignments.compactMap { $0.outfit?.outfit.baseKey }
        XCTAssertEqual(bases.count, Set(bases).count, "a top was planned twice without laundry", file: file, line: line)
        XCTAssertFalse(result.assignments.contains { $0.exceedsWearLimit }, file: file, line: line)
    }
}
