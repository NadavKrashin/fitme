import Foundation
import Testing
@testable import FitEngine

/// Fabric, after seasonal dressing guides: linen is summer cloth, flannel, corduroy, cashmere and fleece are
/// cool-weather
/// cloth, suede and canvas shoes don't belong in the rain, and formal wear isn't denim or technical fabric.
struct FabricTests {
    private func item(_ id: String, _ category: ItemCategory, warmth: Int, _ fabric: Fabric?) -> Item {
        var item = makeItem(id, category, ["#E8E4DA"], formality: 2, warmth: warmth)
        item.fabric = fabric
        return item
    }

    @Test func linenFeelsThinInTheColdEvenUnderALayer() {
        let linen = item("linen", .top, warmth: 1, .linen)
        let cotton = item("cotton", .top, warmth: 1, .cotton)
        #expect(OutfitScorer.pieceFit(linen, feelsLike: 8, layered: true)
            < OutfitScorer.pieceFit(cotton, feelsLike: 8, layered: true))
        #expect(OutfitScorer.pieceFit(linen, feelsLike: 28, layered: false) == 1)
    }

    @Test func corduroyAndFlannelFeelHeavyInTheHeat() {
        let corduroy = item("cords", .bottom, warmth: 3, .corduroy)
        let jeans = item("jeans", .bottom, warmth: 3, .denim)
        #expect(OutfitScorer.pieceFit(corduroy, feelsLike: 25, layered: false)
            < OutfitScorer.pieceFit(jeans, feelsLike: 25, layered: false))
        #expect(OutfitScorer.pieceFit(item("flannel", .top, warmth: 2, .flannel), feelsLike: 26, layered: false) < 1)
    }

    @Test func suedeShoesStayHomeInTheRain() {
        let base = [Fixtures.item("t07"), Fixtures.item("b01"), Fixtures.item("o03")]
        let suede = Outfit(items: base + [item("suede", .shoes, warmth: 2, .suede)])
        let leather = Outfit(items: base + [item("leather", .shoes, warmth: 2, .leather)])
        #expect(OutfitScorer.rainCover(suede, feelsLike: 12) < OutfitScorer.rainCover(leather, feelsLike: 12))
    }

    @Test func formalSkipsDenimAndTechnicalFabric() {
        let context = Fixtures.context(.formal)
        var denimJacket = makeItem("denim blazer", .midLayer, ["#22304D"], formality: 4, warmth: 2)
        denimJacket.fabric = .denim
        #expect(!Rules.isEligible(denimJacket, for: context))
        denimJacket.fabric = .wool
        #expect(Rules.isEligible(denimJacket, for: context))
    }

    @Test func itemsSavedBeforeFabricStillDecode() throws {
        let json = Data(##"""
        {"id": "x", "name": "Tee", "category": "top", "colors": [{"hex": "#FFFFFF"}], "formality": 1, "warmth": 1}
        """##.utf8)
        #expect(try JSONDecoder().decode(Item.self, from: json).fabric == nil)
    }
}
