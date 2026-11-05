import Testing
@testable import FitEngine

struct RulesTests {
    @Test func blazerWithGymShortsIsRejected() {
        let outfit = Fixtures.outfit("t07", "m05", "b11", "s01")
        #expect(Rules.violations(of: outfit, context: Fixtures.context(.smartCasual)).contains(.formalityClash))
    }

    @Test func formalOccasionNeedsDressShoes() {
        let withBoots = Fixtures.outfit("t11", "b07", "s02")
        let withDressShoes = Fixtures.outfit("t11", "b07", "s06")
        #expect(Rules.violations(of: withBoots, context: Fixtures.context(.formal)).contains(.occasionMismatch))
        #expect(Rules.isValid(withDressShoes, context: Fixtures.context(.formal)))
    }

    @Test func coldWeather() {
        let cold = Fixtures.context(.casual, Weather(feelsLikeC: 4))
        #expect(!Rules.isEligible(Fixtures.item("b09"), for: cold), "shorts in the cold")
        #expect(Rules.violations(of: Fixtures.outfit("t01", "b01", "s01"), context: cold).contains(.tooCold))
        #expect(Rules.isValid(Fixtures.outfit("t17", "o05", "b01", "s02"), context: cold))
    }

    @Test func hotWeather() {
        let hot = Fixtures.context(.casual, Weather(feelsLikeC: 30))
        #expect(!Rules.isEligible(Fixtures.item("o04"), for: hot), "wool coat in the heat")
        #expect(!Rules.isEligible(Fixtures.item("t17"), for: hot), "sweater in the heat")
    }

    @Test func harsherWeatherTakesTheWorstOfBoth() {
        let combined = Weather(feelsLikeC: 12, precipitationChance: 0.1)
            .harsher(with: Weather(feelsLikeC: 18, precipitationChance: 0.7))
        #expect(combined == Weather(feelsLikeC: 12, precipitationChance: 0.7))
    }
}
