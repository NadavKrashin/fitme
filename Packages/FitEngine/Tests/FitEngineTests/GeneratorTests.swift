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

struct LayeringTests {
    /// At a feels-like of 20° a shirt with one layer is plenty; a jacket over a cardigan over a shirt is too much.
    @Test(arguments: [16.0, 20, 24])
    func mildDaysNeverStackAJacketOverALayer(feelsLike: Double) {
        let context = Fixtures.context(.casual, Weather(feelsLikeC: feelsLike))
        let outfits = OutfitGenerator().suggest(from: Fixtures.closet, context: context, limit: 10)
        #expect(!outfits.isEmpty)
        for outfit in outfits {
            #expect(outfit.outfit.midLayer == nil || outfit.outfit.outerwear == nil, "\(outfit.id)")
        }
    }

    /// On a dry mild day each layer has to earn its place: without it the outfit would be too cool.
    @Test(arguments: [Occasion.casual, .sport, .smartCasual])
    func dryMildDaysOnlyAddNeededLayers(occasion: Occasion) {
        let weather = Weather(feelsLikeC: 21)
        let context = Fixtures.context(occasion, weather)
        let outfits = OutfitGenerator().suggest(from: Fixtures.closet, context: context, limit: 10)
        #expect(!outfits.isEmpty)
        for suggestion in outfits {
            for layer in [suggestion.outfit.midLayer, suggestion.outfit.outerwear].compactMap(\.self) {
                let without = Outfit(items: suggestion.outfit.items.filter { $0 != layer })
                #expect(Rules.upperWarmth(of: without) < weather.upperWarmthTarget.lowerBound, "\(suggestion.id)")
            }
        }
    }

    @Test func coldDaysStillLayerUp() throws {
        let context = Fixtures.context(.casual, Weather(feelsLikeC: 4))
        let best = try #require(OutfitGenerator().suggest(from: Fixtures.closet, context: context, limit: 1).first)
        #expect(best.outfit.outerwear != nil)
    }
}

struct SwapTests {
    let context = Fixtures.context(.casual, Weather(feelsLikeC: 12))

    @Test func swappingShoesKeepsEverythingElse() throws {
        let outfit = try #require(OutfitGenerator().suggest(from: Fixtures.closet, context: context, limit: 1).first)
        let shoes = try #require(outfit.outfit.shoes)

        let swaps = OutfitGenerator().swaps(
            replacing: shoes,
            in: outfit.outfit,
            from: Fixtures.closet,
            context: context
        )

        #expect(!swaps.isEmpty)
        let others = Set(outfit.outfit.items.filter { $0 != shoes })
        for swap in swaps {
            #expect(Rules.isValid(swap.outfit, context: context), "\(swap.id)")
            #expect(swap.outfit.shoes != shoes)
            #expect(Set(swap.outfit.items.filter { $0.category != .shoes }) == others)
        }
        #expect(swaps.map(\.score) == swaps.map(\.score).sorted(by: >), "best first")
    }

    /// A jacket can be swapped for nothing at all, when the day allows it.
    @Test func aLayerCanBeLeftOff() {
        let mild = Fixtures.context(.casual, Weather(feelsLikeC: 20))
        let outfit = Fixtures.outfit("t05", "o01", "b04", "s01")
        let jacket = Fixtures.item("o01")

        let swaps = OutfitGenerator().swaps(replacing: jacket, in: outfit, from: Fixtures.closet, context: mild)

        #expect(swaps.contains { $0.outfit.outerwear == nil })
    }
}
