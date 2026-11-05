import XCTest
@testable import FitEngine

final class ScorerTests: XCTestCase {
    let scorer = OutfitScorer()
    let smartCasual = OutfitContext(occasion: .smartCasual, weather: .mild, date: Fixtures.startDate)

    func testClassicNeutralsBeatClashingColors() {
        // White oxford + beige chinos + brown loafers vs. purple + green + red.
        let classic = Fixtures.outfit("t07", "b04", "s03")
        let clash = Outfit(items: [
            makeItem("purple", .top, ["#6B2D8C"], formality: 3),
            makeItem("green", .bottom, ["#2F7D3A"], formality: 3),
            makeItem("red", .shoes, ["#C8202F"], formality: 3, warmth: 2),
        ])
        let good = scorer.score(classic, context: smartCasual)
        let bad = scorer.score(clash, context: smartCasual)
        XCTAssertGreaterThan(good.color, 0.8)
        XCTAssertLessThan(bad.color, 0.6)
        XCTAssertGreaterThan(good.total, bad.total + 10)
    }

    func testOneAccentColorIsBetterThanNone() {
        let accent = Fixtures.outfit("t13", "b05", "s01") // rust polo, navy chinos
        let allNeutral = Fixtures.outfit("t07", "b05", "s01")
        XCTAssertGreaterThan(OutfitScorer.colorHarmony(accent), OutfitScorer.colorHarmony(allNeutral))
    }

    func testTwoBoldPatternsArePenalized() {
        let floral = makeItem("floral", .top, ["#F1E6D2", "#C2463E"], pattern: .floral)
        let check = makeItem("check", .bottom, ["#2E6B4F", "#1F2A44"], pattern: .check)
        let creamCheck = makeItem("creamCheck", .bottom, ["#2E6B4F", "#F1E6D2"], pattern: .check)
        let plain = makeItem("plain", .bottom, ["#1C1C1C"])
        XCTAssertEqual(OutfitScorer.patternBalance([floral, plain]), 1)
        XCTAssertLessThan(OutfitScorer.patternBalance([floral, check]), 0.5)
        XCTAssertGreaterThan(OutfitScorer.patternBalance([floral, creamCheck]), OutfitScorer.patternBalance([floral, check]),
                             "patterns that share a color mix better")
    }

    func testStatementBudget() {
        let a = makeItem("a", .top, ["#D9A21B"], statement: true)
        let b = makeItem("b", .bottom, ["#B3262E"], statement: true)
        XCTAssertGreaterThan(OutfitScorer.statementBudget([a]), OutfitScorer.statementBudget([a, b]))
    }

    func testDoubleOversizedIsPenalized() {
        let top = makeItem("top", .top, ["#FFFFFF"], fit: .oversized)
        let baggy = makeItem("baggy", .bottom, ["#1C1C1C"], fit: .oversized)
        let slim = makeItem("slim", .bottom, ["#1C1C1C"], fit: .slim)
        XCTAssertLessThan(OutfitScorer.fitBalance(Outfit(items: [top, baggy])), OutfitScorer.fitBalance(Outfit(items: [top, slim])))
    }

    func testBlazerWithGymShortsIsRejected() {
        let outfit = Fixtures.outfit("t07", "m05", "b11", "s01")
        XCTAssertTrue(Rules.violations(of: outfit, context: smartCasual).contains(.formalityClash))
    }

    func testWeatherRules() {
        let cold = OutfitContext(occasion: .casual, weather: Weather(feelsLikeC: 4), date: Fixtures.startDate)
        XCTAssertFalse(Rules.isEligible(Fixtures.item("b09"), for: cold), "shorts in the cold")
        XCTAssertTrue(Rules.violations(of: Fixtures.outfit("t01", "b01", "s01"), context: cold).contains(.tooCold))
        XCTAssertTrue(Rules.isValid(Fixtures.outfit("t17", "o05", "b01", "s02"), context: cold))

        let hot = OutfitContext(occasion: .casual, weather: Weather(feelsLikeC: 30), date: Fixtures.startDate)
        XCTAssertFalse(Rules.isEligible(Fixtures.item("o04"), for: hot), "wool coat in the heat")
        XCTAssertFalse(Rules.isEligible(Fixtures.item("t17"), for: hot), "sweater in the heat")
    }

    func testFeedbackShiftsAffinity() {
        var profile = StyleProfile()
        let outfit = Fixtures.outfit("t05", "b04", "s01")
        let context = OutfitContext(occasion: .casual, date: Fixtures.startDate, profile: profile)
        let before = scorer.score(outfit, context: context).total
        profile.record(.liked, for: outfit)
        profile.record(.wore, for: outfit)
        var liked = context
        liked.profile = profile
        XCTAssertGreaterThan(scorer.score(outfit, context: liked).total, before)
        profile.record(.disliked, for: outfit)
        profile.record(.disliked, for: outfit)
        XCTAssertLessThan(profile.affinityScore(outfit.coreItems), 0.5)
    }
}
