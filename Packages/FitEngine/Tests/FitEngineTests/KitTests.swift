import Foundation
import Testing
@testable import FitEngine

/// Activity kits: a run or the gym wants training kit, not hiking boots; a hike wants outdoor gear and boots; the
/// beach wants shorts, light tops and sandals, not boots or technical trousers.
struct KitTests {
    private func suggest(_ occasion: Occasion, _ feelsLike: Double) -> [ScoredOutfit] {
        OutfitGenerator().suggest(
            from: Fixtures.closet,
            context: Fixtures.context(occasion, Weather(feelsLikeC: feelsLike))
        )
    }

    /// Hiking trousers and boots only fill in when the closet runs out of training kit (an empty Sport list was
    /// worse: a closet whose only long sport trousers are hiking pants had nothing for a cold run).
    @Test(arguments: [12.0, 24])
    func runsAndWorkoutsReachForHikingGearLast(feelsLike: Double) {
        let suggestions = suggest(.sport, feelsLike)
        #expect(!suggestions.isEmpty)
        let hasHikingGear = suggestions.map { suggestion in
            [suggestion.outfit.bottom, suggestion.outfit.shoes].contains { $0?.styleTags.contains(.outdoor) == true }
        }
        #expect(hasHikingGear.first == false)
        #expect(hasHikingGear == hasHikingGear.sorted { !$0 && $1 }, "\(suggestions.map(\.id))")
    }

    @Test func hikesWearBootsAndOutdoorGear() throws {
        let suggestions = suggest(.hike, 14)
        let best = try #require(suggestions.first)
        #expect(best.outfit.shoes?.styleTags.contains(.outdoor) == true, "\(best.id)")
        for suggestion in suggestions {
            for piece in [suggestion.outfit.top, suggestion.outfit.bottom, suggestion.outfit.shoes].compactMap(\.self) {
                #expect(!piece.styleTags.isDisjoint(with: [.outdoor, .sporty]), "\(suggestion.id)")
            }
        }
    }

    @Test(arguments: [24.0, 30])
    func warmBeachDaysSkipBootsJeansAndHikingGear(feelsLike: Double) {
        let suggestions = suggest(.beach, feelsLike)
        #expect(!suggestions.isEmpty)
        for suggestion in suggestions {
            let outfit = suggestion.outfit
            #expect((outfit.shoes?.warmth ?? 0) < 4, "\(suggestion.id)")
            #expect((outfit.bottom?.warmth ?? 0) < 3, "\(suggestion.id)")
            for piece in outfit.coreItems {
                #expect(!piece.styleTags.contains(.outdoor), "\(suggestion.id)")
            }
        }
    }

    @Test func theBeachLeadsWithSandals() throws {
        let best = try #require(suggest(.beach, 28).first)
        #expect(best.outfit.shoes?.id == "s05", "\(best.id)")
    }
}

/// Running guides: dress for a run as if it were about 6° warmer, since the effort warms you up.
struct ExertionTests {
    /// A closet whose only sport bottoms are running shorts (no leggings or track pants).
    private let closet = Fixtures.closet.filter { !["b12", "b16"].contains($0.id) }

    @Test(arguments: [10.0, 14])
    func coolRunsStillHaveKit(feelsLike: Double) throws {
        let context = Fixtures.context(.sport, Weather(feelsLikeC: feelsLike))
        let best = try #require(OutfitGenerator().suggest(from: closet, context: context).first)
        #expect(best.outfit.bottom?.id == "b11", "\(best.id)")
    }

    @Test func otherOccasionsDressForTheActualTemperature() {
        let context = Fixtures.context(.casual, Weather(feelsLikeC: 14))
        #expect(context.dressingWeather.feelsLikeC == 14)
        #expect(Fixtures.context(.sport, Weather(feelsLikeC: 14)).dressingWeather.feelsLikeC == 20)
    }
}
