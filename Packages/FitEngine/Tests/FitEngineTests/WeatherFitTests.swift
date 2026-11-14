import Foundation
import Testing
@testable import FitEngine

/// Weather for the whole outfit, after temperature dressing guides: shorts from the low twenties up, long trousers
/// below about 20°, light fabrics and shoes in the heat, boots and a real base layer in the cold, and no outfit that
/// is dressed for two seasons at once.
struct WeatherFitTests {
    private func suggest(_ occasion: Occasion, _ feelsLike: Double, rain: Double = 0) -> [ScoredOutfit] {
        let context = Fixtures.context(occasion, Weather(feelsLikeC: feelsLike, precipitationChance: rain))
        return OutfitGenerator().suggest(from: Fixtures.closet, context: context)
    }

    @Test(arguments: [30.0, 34])
    func hotDaysSkipJeansAndWoolTrousers(feelsLike: Double) {
        let suggestions = suggest(.casual, feelsLike)
        #expect(!suggestions.isEmpty)
        for suggestion in suggestions {
            #expect((suggestion.outfit.bottom?.warmth ?? 0) <= 2, "\(suggestion.id)")
        }
    }

    @Test(arguments: [Occasion.casual, .work, .sport])
    func hotDaysSkipBoots(occasion: Occasion) {
        for suggestion in suggest(occasion, 30) {
            #expect((suggestion.outfit.shoes?.warmth ?? 0) < 4, "\(suggestion.id)")
        }
    }

    @Test(arguments: [17.0, 20, 22])
    func noSweaterWithShorts(feelsLike: Double) {
        for suggestion in suggest(.casual, feelsLike) {
            let warmTop = (suggestion.outfit.top?.warmth ?? 0) >= 3
            let shorts = (suggestion.outfit.bottom?.warmth ?? 9) <= 1
            #expect(!(warmTop && shorts), "\(suggestion.id)")
        }
    }

    @Test func coldDaysGetWarmShoesAndARealBaseLayer() throws {
        let best = try #require(suggest(.casual, 0).first)
        #expect((best.outfit.shoes?.warmth ?? 0) >= 3, "\(best.id)")
        #expect((best.outfit.top?.warmth ?? best.outfit.onePiece?.warmth ?? 0) >= 2, "\(best.id)")
    }

    @Test func shortsAndSandalsNeedAWarmDryDay() {
        let shorts = Fixtures.item("b10")
        let sandals = Fixtures.item("s05")
        #expect(!Rules.isEligible(shorts, for: Fixtures.context(.casual, Weather(feelsLikeC: 18))))
        #expect(Rules.isEligible(shorts, for: Fixtures.context(.casual, Weather(feelsLikeC: 24))))
        #expect(!Rules.isEligible(sandals, for: Fixtures.context(.casual, Weather(feelsLikeC: 18))))
        #expect(!Rules.isEligible(
            sandals,
            for: Fixtures.context(.casual, Weather(feelsLikeC: 26, precipitationChance: 0.8))
        ))
    }

    @Test func bootsWaitForCoolOrWetDays() {
        let boots = Fixtures.item("s02")
        #expect(!Rules.isEligible(boots, for: Fixtures.context(.casual, Weather(feelsLikeC: 26))))
        #expect(Rules.isEligible(
            boots,
            for: Fixtures.context(.casual, Weather(feelsLikeC: 26, precipitationChance: 0.8))
        ))
        #expect(Rules.isEligible(boots, for: Fixtures.context(.casual, Weather(feelsLikeC: 12))))
    }
}

/// Rain, after rainwear guides: a water-resistant jacket and shoes that can take a puddle; leather sneakers and
/// suede stay home.
struct RainTests {
    private let rainy = Weather(feelsLikeC: 12, precipitationChance: 0.8)

    @Test func rainyDaysAlwaysBringAJacketThatKeepsWaterOut() {
        let suggestions = OutfitGenerator().suggest(from: Fixtures.closet, context: Fixtures.context(.casual, rainy))
        #expect(!suggestions.isEmpty)
        for suggestion in suggestions {
            #expect(suggestion.outfit.outerwear?.waterResistant == true, "\(suggestion.id)")
        }
    }

    @Test func coldRainPrefersWaterResistantShoes() throws {
        let context = Fixtures.context(.casual, rainy)
        let best = try #require(OutfitGenerator().suggest(from: Fixtures.closet, context: context).first)
        #expect(best.outfit.shoes?.waterResistant == true, "\(best.id)")
    }

    /// The same outfit twice, once in pieces that keep water out.
    @Test func coverMattersMoreThanAFewPoints() {
        let context = Fixtures.context(.casual, rainy)
        let outfit = { (waterResistant: Bool) in
            Outfit(items: [
                Fixtures.item("t07"),
                Fixtures.item("b01"),
                Item(
                    id: "jacket",
                    name: "jacket",
                    category: .outerwear,
                    colors: [ItemColor(hex: "#27324A")],
                    formality: 2,
                    warmth: 3,
                    waterResistant: waterResistant
                ),
                Item(
                    id: "boots",
                    name: "boots",
                    category: .shoes,
                    colors: [ItemColor(hex: "#6B4226")],
                    formality: 2,
                    warmth: 3,
                    waterResistant: waterResistant
                ),
            ])
        }
        let covered = OutfitScorer().score(outfit(true), context: context)
        let exposed = OutfitScorer().score(outfit(false), context: context)
        #expect(covered.total > exposed.total + 8)
    }
}
