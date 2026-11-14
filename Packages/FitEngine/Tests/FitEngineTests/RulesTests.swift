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

    /// From a trial: a rain shell over a hoodie on a dry 21° day. The hoodie is warm enough alone, so the shell only
    /// belongs when rain is likely.
    @Test func aMildDayOnlyTakesALayerThatsNeeded() {
        let withShell = Fixtures.outfit("t19", "o06", "b16", "s04")
        let dry = Fixtures.context(.sport, Weather(feelsLikeC: 21, precipitationChance: 0))
        let wet = Fixtures.context(.sport, Weather(feelsLikeC: 21, precipitationChance: 0.6))
        #expect(Rules.violations(of: withShell, context: dry).contains(.unneededLayer))
        #expect(Rules.isValid(withShell, context: wet))
        #expect(Rules.isValid(Fixtures.outfit("t19", "b16", "s04"), context: dry))
    }

    @Test func aLightLayerOverATeeIsStillFineOnAMildDay() {
        let tee = Fixtures.item("t01")
        let mild = Fixtures.context(.casual, Weather(feelsLikeC: 18))
        let layered = Fixtures.closet.filter { $0.category == .outerwear || $0.category == .midLayer }
            .map { Outfit(items: [tee, $0, Fixtures.item("b01"), Fixtures.item("s01")]) }
        #expect(layered.contains { Rules.isValid($0, context: mild) })
    }

    @Test func harsherWeatherTakesTheWorstOfBoth() {
        let combined = Weather(feelsLikeC: 12, precipitationChance: 0.1)
            .harsher(with: Weather(feelsLikeC: 18, precipitationChance: 0.7))
        #expect(combined == Weather(feelsLikeC: 12, precipitationChance: 0.7))
    }
}

struct LegCoverageTests {
    @Test func lightDressesAreNotSuggestedInTheCold() {
        let cold = Fixtures.context(.casual, Weather(feelsLikeC: 7, precipitationChance: 0.6))
        #expect(!Rules.isEligible(Fixtures.item("d03"), for: cold), "sundress at 7°C")
        #expect(!Rules.isEligible(Fixtures.item("d02"), for: cold), "light shirt dress at 7°C")
        #expect(Rules.isEligible(Fixtures.item("d03"), for: Fixtures.context(.casual, Weather(feelsLikeC: 22))))
    }
}
