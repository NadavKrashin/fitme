import Foundation
import Testing
@testable import FitEngine

/// Shoe pairing as menswear guides teach it: the shoes match the outfit's dress code, brown goes with navy and earth
/// tones, black with black and charcoal and with formal wear, and sneakers stay with casual trousers.
struct ShoeTests {
    private let whiteShirt = makeItem("shirt", .top, ["#F7F7F5"], formality: 3, warmth: 2)
    private let brownShoes = makeItem("brown", .shoes, ["#6B4226"], formality: 3, warmth: 2)
    private let blackShoes = makeItem("black", .shoes, ["#101010"], formality: 3, warmth: 2)

    private func pairing(_ bottomHex: String, _ shoes: Item) -> Double {
        let trousers = makeItem("trousers", .bottom, [bottomHex], formality: 3, warmth: 2)
        return OutfitScorer.shoePairing(Outfit(items: [whiteShirt, trousers, shoes]), occasion: .smartCasual)
    }

    @Test func navyTrousersTakeBrownShoesOverBlack() {
        #expect(pairing("#27324A", brownShoes) > pairing("#27324A", blackShoes))
    }

    @Test func beigeTrousersTakeBrownShoesOverBlack() {
        #expect(pairing("#C8B48F", brownShoes) > pairing("#C8B48F", blackShoes))
    }

    @Test func charcoalTrousersTakeBlackShoesOverBrown() {
        #expect(pairing("#2E2E30", blackShoes) > pairing("#2E2E30", brownShoes))
    }

    @Test func sneakersDontSuitTailoredTrousers() {
        let sneakers = OutfitScorer.shoePairing(Fixtures.outfit("t07", "b06", "s01"), occasion: .smartCasual)
        let loafers = OutfitScorer.shoePairing(Fixtures.outfit("t07", "b06", "s03"), occasion: .smartCasual)
        #expect(loafers > sneakers)
    }

    @Test func formalOutfitsWearBlackDressShoes() throws {
        let suggestions = OutfitGenerator().suggest(from: Fixtures.closet, context: Fixtures.context(.formal))
        let best = try #require(suggestions.first)
        #expect(best.outfit.shoes?.id == "s06", "\(best.id)")
    }

    /// Two outfits that score the same used to be ordered by item ID, so the same pair of shoes won every tie.
    @Test func equalOutfitsTakeTurnsDayByDay() {
        let tee = makeItem("tee", .top, ["#F5F5F2"], formality: 2)
        let chinos = makeItem("chinos", .bottom, ["#27324A"], formality: 2, warmth: 2)
        let twins = ["a", "b"].map { makeItem("sneaker-\($0)", .shoes, ["#F4F4F2"], formality: 2, warmth: 2) }
        let leaders = Set((0 ..< 14).compactMap { day -> String? in
            let date = Fixtures.startDate.addingTimeInterval(Double(day) * 86400)
            let context = OutfitContext(occasion: .casual, weather: Weather(feelsLikeC: 24), date: date)
            return OutfitGenerator().suggest(from: [tee, chinos] + twins, context: context, limit: 1).first?
                .outfit.shoes?.id
        })
        #expect(leaders == ["sneaker-a", "sneaker-b"])
    }
}
