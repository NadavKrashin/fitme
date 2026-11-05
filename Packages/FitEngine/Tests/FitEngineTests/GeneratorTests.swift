import XCTest
@testable import FitEngine

final class GeneratorTests: XCTestCase {
    let generator = OutfitGenerator()

    func testCasualSuggestionsAreValidAndVaried() {
        let context = OutfitContext(occasion: .casual, weather: .mild, date: Fixtures.startDate)
        let outfits = generator.suggest(from: Fixtures.closet, context: context, limit: 5)
        XCTAssertEqual(outfits.count, 5)
        for o in outfits {
            XCTAssertTrue(Rules.isValid(o.outfit, context: context), o.id)
            XCTAssertGreaterThan(o.score, 70, o.id)
        }
        XCTAssertEqual(Set(outfits.map(\.outfit.baseKey)).count, 5, "each suggestion should have a different top")
    }

    func testFormalOccasionUsesFormalPieces() {
        let context = OutfitContext(occasion: .formal, weather: .mild, date: Fixtures.startDate)
        let outfits = generator.suggest(from: Fixtures.closet, context: context, limit: 3)
        XCTAssertFalse(outfits.isEmpty)
        for o in outfits {
            XCTAssertGreaterThanOrEqual(o.outfit.shoes!.formality, 4, o.id)
            XCTAssertFalse(o.outfit.items.contains { $0.formality <= 1 }, o.id)
        }
    }

    func testSportOnlyUsesSportswear() {
        let context = OutfitContext(occasion: .sport, weather: Weather(feelsLikeC: 24), date: Fixtures.startDate)
        let outfits = generator.suggest(from: Fixtures.closet, context: context, limit: 3)
        XCTAssertFalse(outfits.isEmpty)
        for o in outfits {
            XCTAssertTrue(o.outfit.coreItems.filter { $0.category != .outerwear }.allSatisfy { $0.styleTags.contains(.sporty) }, o.id)
        }
    }

    func testColdRainyDayGetsAWaterResistantLayer() {
        let context = OutfitContext(occasion: .casual, weather: Weather(feelsLikeC: 6, precipitationChance: 0.8), date: Fixtures.startDate)
        let best = generator.suggest(from: Fixtures.closet, context: context, limit: 1).first!
        XCTAssertNotNil(best.outfit.outerwear)
        XCTAssertTrue([best.outfit.outerwear, best.outfit.shoes].contains { $0?.waterResistant == true }, best.id)
    }

    func testBuildAroundAnItem() {
        let mustard = Fixtures.item("t21")
        let context = OutfitContext(occasion: .casual, weather: Weather(feelsLikeC: 14), date: Fixtures.startDate)
        let outfits = generator.suggest(from: Fixtures.closet, context: context, limit: 3, mustInclude: mustard)
        XCTAssertFalse(outfits.isEmpty)
        XCTAssertTrue(outfits.allSatisfy { $0.outfit.contains(mustard) })
    }
}
