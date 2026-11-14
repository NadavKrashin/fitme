import Foundation
import Testing
@testable import FitEngine

/// Color as menswear color guides teach it: neutrals never clash with each other (except navy with black, which
/// looks accidentally dark), some neutral-and-color pairings are classics (navy with burgundy or rust, grey with
/// pink, olive with burgundy), two colors need a known pairing or related hues, and about three colors read as
/// deliberate. Neither neutral nor colorful wins by itself; how much color to wear is a matter of mood.
struct ColorTests {
    /// White oxford, navy chinos, brown loafers.
    private let neutral = Fixtures.outfit("t07", "b05", "s03")
    /// Rust polo, navy chinos, brown loafers: rust with navy is a classic.
    private let accent = Fixtures.outfit("t13", "b05", "s03")

    private func outfit(_ top: String, _ bottom: String, shoes: String = "#6B4226") -> Outfit {
        Outfit(items: [
            makeItem("top", .top, [top]),
            makeItem("bottom", .bottom, [bottom]),
            makeItem("shoes", .shoes, [shoes], warmth: 2),
        ])
    }

    @Test func aClassicAccentScoresAsWellAsAllNeutrals() {
        #expect(isClose(OutfitScorer.colorHarmony(accent), OutfitScorer.colorHarmony(neutral), tolerance: 0.02))
    }

    @Test func classicPairingsBeatPoorOnes() {
        let navy = "#27324A", burgundy = "#6B1F2E", grey = "#8E8E8E", pink = "#F2B8C6"
        let red = "#B3262E", green = "#2F7D3A", purple = "#6B2D8C", olive = "#5A6140"
        #expect(OutfitScorer.colorHarmony(outfit(burgundy, navy)) > OutfitScorer.colorHarmony(outfit(red, green)))
        #expect(OutfitScorer.colorHarmony(outfit(pink, grey)) > OutfitScorer.colorHarmony(outfit(purple, olive)))
    }

    @Test func navyWithBlackLooksAccidental() {
        let navyTop = "#22304D"
        #expect(
            OutfitScorer.colorHarmony(outfit(navyTop, "#161616", shoes: "#101010"))
                < OutfitScorer.colorHarmony(outfit(navyTop, "#8E8E8E", shoes: "#101010"))
        )
    }

    @Test func aNeutralMoodPushesAccentsBack() {
        #expect(OutfitScorer.colorHarmony(accent, palette: .neutral) < OutfitScorer.colorHarmony(accent) - 0.15)
        #expect(OutfitScorer.colorHarmony(neutral, palette: .neutral) == OutfitScorer.colorHarmony(neutral))
    }

    @Test func aColorfulMoodPutsAnAccentFirst() {
        #expect(
            OutfitScorer.colorHarmony(accent, palette: .colorful)
                > OutfitScorer.colorHarmony(neutral, palette: .colorful)
        )
    }

    @Test func moreThanThreeColorsLooksBusy() {
        let three = Outfit(items: [
            makeItem("white", .top, ["#F7F7F5"]),
            makeItem("navy", .bottom, ["#27324A"]),
            makeItem("brown", .shoes, ["#6B4226"], warmth: 2),
        ])
        let five = Outfit(items: three.items + [
            makeItem("grey", .midLayer, ["#8E8E8E"], warmth: 2),
            makeItem("olive", .outerwear, ["#5A6140"], warmth: 2),
        ])
        #expect(OutfitScorer.colorHarmony(five) < OutfitScorer.colorHarmony(three))
    }

    /// Mixed mood: every suggestion is well put together in color, whether it's all neutrals or has an accent.
    @Test func everydaySuggestionsAreWellColoredEitherWay() {
        let suggestions = suggest(.balanced)
        #expect(suggestions.count == 5)
        for suggestion in suggestions {
            #expect(suggestion.breakdown.color >= 0.85, "\(suggestion.id)")
        }
    }

    @Test func aNeutralMoodSuggestsOnlyNeutrals() {
        let suggestions = suggest(.neutral)
        #expect(!suggestions.isEmpty)
        #expect(suggestions.allSatisfy { !Self.hasAccent($0.outfit) }, "\(suggestions.map(\.id))")
    }

    @Test func aColorfulMoodLeadsWithColor() throws {
        let best = try #require(suggest(.colorful).first)
        #expect(Self.hasAccent(best.outfit), "\(best.id)")
    }

    private func suggest(_ palette: Palette) -> [ScoredOutfit] {
        var context = Fixtures.context(.casual, Weather(feelsLikeC: 20))
        context.palette = palette
        return OutfitGenerator().suggest(from: Fixtures.closet, context: context)
    }

    static func hasAccent(_ outfit: Outfit) -> Bool {
        outfit.coreItems.flatMap(\.significantColors).contains { $0.lch.neutrality == .chromatic }
    }
}
