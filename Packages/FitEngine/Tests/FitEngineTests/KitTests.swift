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

    @Test(arguments: [12.0, 24])
    func runsAndWorkoutsSkipHikingGear(feelsLike: Double) {
        let suggestions = suggest(.sport, feelsLike)
        #expect(!suggestions.isEmpty)
        for suggestion in suggestions {
            for piece in [suggestion.outfit.bottom, suggestion.outfit.shoes].compactMap(\.self) {
                #expect(!piece.styleTags.contains(.outdoor), "\(suggestion.id)")
            }
        }
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
