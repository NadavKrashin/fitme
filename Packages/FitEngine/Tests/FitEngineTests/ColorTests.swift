import Foundation
import Testing
@testable import FitEngine

/// Color as menswear guides teach it: outfits are built on neutrals (navy, grey, white, beige, brown, olive), an
/// accent color is a choice rather than a requirement, about three colors read as deliberate, and how much color to
/// wear is a matter of mood.
struct ColorTests {
    /// White oxford, navy chinos, brown loafers.
    private let neutral = Fixtures.outfit("t07", "b05", "s03")
    /// The same with a rust polo instead of the oxford.
    private let accent = Fixtures.outfit("t13", "b05", "s03")

    @Test func aNeutralOutfitScoresAtLeastAsWellAsOneWithAnAccent() {
        #expect(OutfitScorer.colorHarmony(neutral) >= OutfitScorer.colorHarmony(accent))
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

    @Test func everydaySuggestionsAreMostlyNeutral() {
        let suggestions = suggest(.balanced)
        #expect(suggestions.count == 5)
        #expect(suggestions.count(where: { !Self.hasAccent($0.outfit) }) >= 3, "\(suggestions.map(\.id))")
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
