import Testing
@testable import FitEngine

struct AnalyzerTests {
    let analyzer = ClosetAnalyzer()
    let tee = makeItem("tee", .top, ["#F5F5F2"])
    let shirt = makeItem("shirt", .top, ["#A9C4E0"], formality: 3, warmth: 2)
    let chinos = makeItem("chinos", .bottom, ["#27324A"], formality: 2, warmth: 2)
    let sneakers = makeItem("sneakers", .shoes, ["#F4F4F2"], warmth: 2)

    @Test func aPieceThatClashesWithEverythingIsHardToStyle() {
        let sequins = makeItem("sequins", .top, ["#C2463E"], pattern: .graphic, formality: 5, warmth: 2)
        let insights = analyzer.analyze([tee, shirt, chinos, sneakers, sequins], candidates: [])

        #expect(insights.looksByItem["sequins"] == 0)
        #expect(insights.hardToStyle.first == "sequins")
        #expect((insights.looksByItem["chinos"] ?? 0) > (insights.looksByItem["sequins"] ?? 0))
    }

    @Test func withoutShoesTheBestGapIsShoes() throws {
        let insights = analyzer.analyze([tee, shirt, chinos])

        let best = try #require(insights.gaps.first)
        #expect(best.item.category == .shoes)
        #expect(Set(best.rescues) == ["tee", "shirt", "chinos"])
        #expect(best.newOutfits > 0)
    }

    @Test func stapleAlreadyOwnedIsNotSuggested() {
        let insights = analyzer.analyze([tee, shirt, chinos, sneakers])
        #expect(!insights.gaps.contains { $0.item.id == "gap-white-sneakers" })
    }

    /// A coat is worth what it adds: plenty in a closet with no coat, little next to one that does the same job.
    @Test func aCoatCountsForTheColdDaysItOpensUp() throws {
        let camel = makeItem("camel coat", .outerwear, ["#C19A6B"], formality: 3, warmth: 5)
        let charcoal = makeItem("charcoal coat", .outerwear, ["#3A3A3C"], formality: 3, warmth: 5)
        let jumper = makeItem("jumper", .top, ["#8A8D91"], formality: 2, warmth: 3)
        let base = [tee, shirt, jumper, chinos, sneakers]

        let coatless = try #require(analyzer.analyze(base, candidates: [camel]).gaps.first)
        let alongside = analyzer.analyze(base + [charcoal], candidates: [camel]).gaps.first

        #expect(coatless.newOutfits > alongside?.newOutfits ?? 0)
    }

    /// A look is the base and shoes; the coat over it on a cold day doesn't make it a different look.
    @Test func layersDontMakeANewLook() {
        let coat = makeItem("coat", .outerwear, ["#3A3A3C"], warmth: 5)
        #expect(
            ClosetAnalyzer.lookKey(Outfit(items: [tee, chinos, sneakers, coat]))
                == ClosetAnalyzer.lookKey(Outfit(items: [tee, chinos, sneakers]))
        )
    }

    @Test func aPieceInTheWashStillCounts() {
        var washing = chinos
        washing.isAvailable = false
        let insights = analyzer.analyze([tee, shirt, washing, sneakers], candidates: [])
        #expect((insights.looksByItem["chinos"] ?? 0) > 0)
    }

    @Test func workhorsesAreThePiecesInTheMostLooks() throws {
        let insights = analyzer.analyze(Fixtures.closet, candidates: [])
        let top = try #require(insights.workhorses(limit: 1).first)
        #expect(insights.looksByItem.values.allSatisfy { $0 <= insights.looksByItem[top] ?? 0 })
        #expect(insights.totalLooks >= insights.looksByItem[top] ?? 0)
    }
}
