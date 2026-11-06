import FitEngine
import Foundation
import Observation

/// Inputs and results for the "what do I wear today" screen.
@MainActor
@Observable
final class TodayModel {
    enum WeatherState: Equatable {
        case idle
        case loading
        case loaded(DayForecast)
        case failed(String)
    }

    enum StylistState: Equatable {
        case idle
        case loading
        case picked([StylistPick])
        case failed(String)
    }

    static let temperatureRange: ClosedRange<Double> = -10 ... 40
    private nonisolated static let suggestionCount = 5
    /// The stylist chooses from more candidates than are shown, so it can surface outfits the scorer ranked lower.
    private nonisolated static let stylistCandidateCount = 12
    /// Chance of rain to assume when the user says it's raining.
    private static let rainyChance = 0.8

    var occasion: Occasion = .casual
    var feelsLikeC = 20.0
    var isRainy = false
    private(set) var suggestions: [ScoredOutfit] = []
    /// Reactions given this session, by outfit id.
    private(set) var feedback: [String: OutfitFeedback] = [:]
    private(set) var weather: WeatherState = .idle
    private(set) var stylist: StylistState = .idle

    /// When set, every suggestion is built around this item ("Outfits with this").
    let anchor: Item?
    private let generator: OutfitGenerator
    private let weatherService: any WeatherProviding
    private let outfitStylist: any OutfitStylist

    init(
        generator: OutfitGenerator,
        weatherService: any WeatherProviding,
        stylist: any OutfitStylist,
        anchor: Item? = nil
    ) {
        self.anchor = anchor
        self.generator = generator
        self.weatherService = weatherService
        outfitStylist = stylist
    }

    func context(profile: StyleProfile? = nil, date: Date = .now) -> OutfitContext {
        OutfitContext(
            occasion: occasion,
            weather: Weather(feelsLikeC: feelsLikeC, precipitationChance: isRainy ? Self.rainyChance : 0),
            date: date,
            profile: profile
        )
    }

    // MARK: Suggestions

    func refresh(closet: [Item], profile: StyleProfile) async {
        let found = await Self.suggest(
            generator: generator,
            closet: closet,
            context: context(profile: profile),
            limit: Self.suggestionCount,
            anchor: anchor
        )
        suggestions = found.filter { feedback[$0.id] != .disliked }
        stylist = .idle
    }

    /// Records a reaction. Disliked outfits disappear from the list right away.
    func react(_ reaction: OutfitFeedback, to outfit: ScoredOutfit, recorder: FeedbackRecorder) {
        feedback[outfit.id] = reaction
        recorder.record(reaction, for: outfit.outfit)
        if reaction == .disliked {
            suggestions.removeAll { $0.id == outfit.id }
        }
    }

    // MARK: Weather

    /// Fills temperature and rain from the forecast for the user's location. Manual edits still win afterwards.
    func loadWeather() async {
        weather = .loading
        do {
            let forecast = try await weatherService.forecastHere()
            feelsLikeC = forecast.feelsLikeNowC.rounded().clamped(to: Self.temperatureRange)
            isRainy = Weather(feelsLikeC: forecast.feelsLikeNowC, precipitationChance: forecast.precipitationChance)
                .isRainy
            weather = .loaded(forecast)
        } catch {
            weather = .failed((error as? WeatherError)?.userMessage ?? WeatherError.unavailable.userMessage)
        }
    }

    // MARK: Stylist

    func askStylist(closet: [Item], profile: StyleProfile) async {
        stylist = .loading
        let context = context(profile: profile)
        let candidates = await Self.suggest(
            generator: generator,
            closet: closet,
            context: context,
            limit: Self.stylistCandidateCount,
            anchor: anchor
        )
        guard !candidates.isEmpty else {
            stylist = .failed("Nothing in your closet fits this occasion and weather.")
            return
        }
        do {
            stylist = try await .picked(outfitStylist.pick(from: candidates, context: context))
        } catch {
            stylist = .failed((error as? ClaudeError)?.userMessage ?? "The stylist couldn't answer. Try again.")
        }
    }

    /// Runs off the main actor: outfit search over a full closet takes long enough to drop frames.
    @concurrent
    private nonisolated static func suggest(
        generator: OutfitGenerator,
        closet: [Item],
        context: OutfitContext,
        limit: Int,
        anchor: Item?
    ) async -> [ScoredOutfit] {
        generator.suggest(from: closet, context: context, limit: limit, mustInclude: anchor)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
