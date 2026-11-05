import FitEngine
import Foundation
import Observation

/// Inputs and results for the "what do I wear today" screen.
@MainActor
@Observable
final class TodayModel {
    static let temperatureRange: ClosedRange<Double> = -10 ... 40
    private nonisolated static let suggestionCount = 5
    /// Chance of rain to assume when the user says it's raining.
    private static let rainyChance = 0.8

    var occasion: Occasion = .casual
    var feelsLikeC = 20.0
    var isRainy = false
    private(set) var suggestions: [ScoredOutfit] = []

    private let generator: OutfitGenerator

    init(generator: OutfitGenerator) {
        self.generator = generator
    }

    var context: OutfitContext {
        OutfitContext(
            occasion: occasion,
            weather: Weather(feelsLikeC: feelsLikeC, precipitationChance: isRainy ? Self.rainyChance : 0)
        )
    }

    func refresh(closet: [Item]) async {
        suggestions = await Self.suggest(generator: generator, closet: closet, context: context)
    }

    /// Runs off the main actor: outfit search over a full closet takes long enough to drop frames.
    @concurrent
    private nonisolated static func suggest(
        generator: OutfitGenerator,
        closet: [Item],
        context: OutfitContext
    ) async -> [ScoredOutfit] {
        generator.suggest(from: closet, context: context, limit: suggestionCount)
    }
}
