import Foundation
import Testing
@testable import FitEngine

/// Dress codes as menswear guides define them: formal is a dress shirt, tailored trousers, a tailored jacket and dress
/// shoes; work is business casual (collared shirts and fine knits, chinos, wool trousers or dark denim, leather shoes);
/// smart casual and dates leave gym and hiking gear at home.
struct DressCodeTests {
    private func suggest(_ occasion: Occasion, _ feelsLike: Double) -> [ScoredOutfit] {
        OutfitGenerator().suggest(
            from: Fixtures.closet,
            context: Fixtures.context(occasion, Weather(feelsLikeC: feelsLike))
        )
    }

    @Test(arguments: [10.0, 18, 28])
    func formalIsADressShirtUnderATailoredJacket(feelsLike: Double) {
        let suggestions = suggest(.formal, feelsLike)
        #expect(!suggestions.isEmpty)
        for suggestion in suggestions {
            let outfit = suggestion.outfit
            #expect((outfit.top?.formality ?? outfit.onePiece?.formality ?? 0) >= 4, "\(suggestion.id)")
            #expect((outfit.bottom?.formality ?? 5) >= 4, "\(suggestion.id)")
            if outfit.onePiece == nil {
                #expect((outfit.midLayer?.formality ?? 0) >= 4, "\(suggestion.id)")
            }
        }
    }

    @Test(arguments: [20.0, 29])
    func workIsBusinessCasual(feelsLike: Double) {
        let suggestions = suggest(.work, feelsLike)
        #expect(!suggestions.isEmpty)
        for suggestion in suggestions {
            let outfit = suggestion.outfit
            for piece in [outfit.top, outfit.bottom, outfit.shoes].compactMap(\.self) {
                #expect(piece.styleTags.isDisjoint(with: [.sporty, .outdoor]), "\(suggestion.id)")
            }
            #expect(outfit.top.map { $0.pattern != .graphic && !$0.isStatement && $0.formality >= 2 } ?? true)
            if let bottom = outfit.bottom {
                #expect(bottom.warmth > 1, "no shorts: \(suggestion.id)")
                #expect(!Rules.isLightDenim(bottom), "no light-wash jeans: \(suggestion.id)")
            }
        }
    }

    @Test(arguments: [Occasion.smartCasual, .date])
    func smartCasualLeavesGymAndHikingGearAtHome(occasion: Occasion) {
        for suggestion in suggest(occasion, 20) {
            let outfit = suggestion.outfit
            for piece in [outfit.top, outfit.bottom, outfit.shoes].compactMap(\.self) {
                #expect(piece.styleTags.isDisjoint(with: [.sporty, .outdoor]), "\(suggestion.id)")
            }
            #expect(outfit.top?.pattern != .graphic, "\(suggestion.id)")
        }
    }

    @Test func aSuitJacketOnlyGoesWithItsTrousers() {
        let shirt = makeItem("white shirt", .top, ["#FFFFFF"], formality: 5, warmth: 2)
        let jacket = makeItem("charcoal suit jacket", .midLayer, ["#36383C"], formality: 5, warmth: 2)
        let suitTrousers = makeItem("charcoal suit trousers", .bottom, ["#36383C"], formality: 5, warmth: 2)
        let greyTrousers = makeItem("grey wool trousers", .bottom, ["#8E8E8E"], formality: 4, warmth: 3)
        let shoes = makeItem("black oxfords", .shoes, ["#101010"], formality: 5, warmth: 2)
        let context = Fixtures.context(.formal, Weather(feelsLikeC: 15))

        #expect(Rules.isValid(Outfit(items: [shirt, jacket, suitTrousers, shoes]), context: context))
        #expect(Rules.violations(of: Outfit(items: [shirt, jacket, greyTrousers, shoes]), context: context)
            .contains(.splitSuit))
    }

    @Test func swimsuitsAndTracksuitsAreNotSuits() {
        #expect(!makeItem("navy tracksuit top", .midLayer, ["#22304D"]).isSuitPiece)
        #expect(makeItem("navy suit trousers", .bottom, ["#22304D"]).isSuitPiece)
    }
}
