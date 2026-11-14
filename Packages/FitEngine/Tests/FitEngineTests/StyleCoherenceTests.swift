import Foundation
import Testing
@testable import FitEngine

/// Style coherence: pieces from aesthetics that mix well (classic with preppy or minimal, street with sporty, outdoor
/// workwear with classic or street) beat ones that clash (a technical fleece over a floral camp shirt).
struct StyleCoherenceTests {
    @Test func aesthesticsThatMixBeatOnesThatClash() {
        #expect(StyleTag.compatibility(.classic, .preppy) > StyleTag.compatibility(.sporty, .classic))
        #expect(StyleTag.compatibility(.street, .sporty) > StyleTag.compatibility(.outdoor, .boho))
        #expect(StyleTag.compatibility(.minimal, .minimal) == 1)
    }

    @Test func aFleeceOverAFloralShirtClashes() {
        let clash = Fixtures.outfit("t16", "m04", "b01", "s01") // floral camp shirt under a green fleece
        let coherent = Fixtures.outfit("t16", "m01", "b01", "s01") // the same shirt under a grey cardigan
        #expect(OutfitScorer.styleCoherence(clash.coreItems) < OutfitScorer.styleCoherence(coherent.coreItems))
    }

    @Test func untaggedPiecesDontCount() {
        #expect(OutfitScorer.styleCoherence(Fixtures.outfit("t03", "b01", "s08").coreItems) == 1)
    }

    /// A grey fleece and a grey cardigan of the same weight, either of which could go over a floral camp shirt:
    /// the cardigan suits it.
    @Test func theLayerThatSuitsTheShirtWins() throws {
        var fleece = makeItem("grey fleece", .midLayer, ["#8E8E8E"], formality: 2, warmth: 2)
        fleece.styleTags = [.outdoor, .sporty]
        var cardigan = makeItem("grey cardigan", .midLayer, ["#8E8E8E"], formality: 2, warmth: 2)
        cardigan.styleTags = [.classic]
        let closet = [Fixtures.item("t16"), fleece, cardigan, Fixtures.item("b04"), Fixtures.item("s01")]
        for day in 0 ..< 4 {
            let date = Fixtures.startDate.addingTimeInterval(Double(day) * 86400)
            let context = OutfitContext(occasion: .casual, weather: Weather(feelsLikeC: 15), date: date)
            let best = try #require(OutfitGenerator().suggest(from: closet, context: context, limit: 1).first)
            #expect(best.outfit.midLayer == cardigan, "\(best.id)")
        }
    }

    @Test(arguments: [6.0, 12])
    func casualSuggestionsDontMixBohoWithTechnicalGear(feelsLike: Double) {
        let context = Fixtures.context(.casual, Weather(feelsLikeC: feelsLike))
        for suggestion in OutfitGenerator().suggest(from: Fixtures.closet, context: context) {
            let tags = suggestion.outfit.coreItems.map(\.styleTags)
            let boho = tags.contains { $0.contains(.boho) }
            let technical = tags.contains { !$0.isDisjoint(with: [.outdoor, .sporty]) }
            #expect(!(boho && technical), "\(suggestion.id)")
        }
    }
}
