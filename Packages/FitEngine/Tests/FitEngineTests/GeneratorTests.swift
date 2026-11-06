import Testing
@testable import FitEngine

struct GeneratorTests {
    let generator = OutfitGenerator()

    @Test func casualSuggestionsAreValidGoodAndVaried() {
        let context = Fixtures.context(.casual)
        let outfits = generator.suggest(from: Fixtures.closet, context: context, limit: 5)

        #expect(outfits.count == 5)
        for outfit in outfits {
            #expect(Rules.isValid(outfit.outfit, context: context), "\(outfit.id)")
            #expect(outfit.score > 70, "\(outfit.id)")
        }
        #expect(Set(outfits.map(\.outfit.baseKey)).count == 5, "each suggestion should have a different top")
    }

    @Test func formalOccasionUsesFormalPieces() {
        let outfits = generator.suggest(from: Fixtures.closet, context: Fixtures.context(.formal), limit: 3)
        #expect(!outfits.isEmpty)
        for outfit in outfits {
            #expect((outfit.outfit.shoes?.formality ?? 0) >= 4, "\(outfit.id)")
            #expect(!outfit.outfit.items.contains { $0.formality <= 1 }, "\(outfit.id)")
        }
    }

    @Test func sportOnlyUsesSportswear() {
        let context = Fixtures.context(.sport, Weather(feelsLikeC: 24))
        let outfits = generator.suggest(from: Fixtures.closet, context: context, limit: 3)
        #expect(!outfits.isEmpty)
        for outfit in outfits {
            let worn = outfit.outfit.coreItems.filter { $0.category != .outerwear }
            #expect(worn.allSatisfy { $0.styleTags.contains(.sporty) }, "\(outfit.id)")
        }
    }

    @Test func coldRainyDayGetsAWaterResistantLayer() throws {
        let context = Fixtures.context(.casual, Weather(feelsLikeC: 6, precipitationChance: 0.8))
        let best = try #require(generator.suggest(from: Fixtures.closet, context: context, limit: 1).first)
        #expect(best.outfit.outerwear != nil)
        #expect([best.outfit.outerwear, best.outfit.shoes].contains { $0?.waterResistant == true }, "\(best.id)")
    }

    @Test func buildsAroundAChosenItem() {
        let mustard = Fixtures.item("t21")
        let context = Fixtures.context(.casual, Weather(feelsLikeC: 14))
        let outfits = generator.suggest(from: Fixtures.closet, context: context, limit: 3, mustInclude: mustard)
        #expect(!outfits.isEmpty)
        #expect(outfits.allSatisfy { $0.outfit.contains(mustard) })
    }
}

struct AlternativesTests {
    /// A swap should offer a different look first, not the same top and bottom with other shoes.
    @Test func alternativesLeadWithADifferentTop() throws {
        let trip = Fixtures.days(5, weather: Weather(feelsLikeC: 18), occasions: [.casual])
        let packed = PackingOptimizer().pack(closet: Fixtures.closet, trip: trip)
        let current = try #require(packed.assignments.first?.outfit).outfit
        let context = Fixtures.context(.casual, Weather(feelsLikeC: 18))

        let alternatives = OutfitGenerator().alternatives(to: current, from: packed.items, context: context)

        #expect(!alternatives.isEmpty)
        #expect(alternatives.allSatisfy { $0.id != current.id && $0.outfit.items.allSatisfy(packed.items.contains) })
        #expect(alternatives.first?.outfit.baseKey != current.baseKey)
    }
}
