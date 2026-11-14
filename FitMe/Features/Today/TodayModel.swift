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

    enum CalendarState: Equatable {
        /// Not read: access was refused, or the screen isn't today's.
        case unavailable
        case notAsked
        case hints([CalendarHint])
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
    /// How much color the user is in the mood for; Mixed (judged on merit) by default.
    var palette: Palette = .balanced
    /// The forecast's feels-like now and its range for the rest of the day. The range applies while the slider still
    /// shows the forecast's "now"; a temperature set by hand is dressed for exactly.
    private var forecastNowC: Double?
    private var forecastRange: ClosedRange<Double>?
    private(set) var suggestions: [ScoredOutfit] = []
    /// Outfits hidden with 👎 this session.
    private(set) var dismissed: Set<String> = []
    /// The latest confirmation to show, if any.
    var toast: Toast?
    private(set) var weather: WeatherState = .idle
    private(set) var stylist: StylistState = .idle
    private(set) var calendarHints: CalendarState = .unavailable
    /// The event chosen with "Dress for it"; other events may call for the same occasion.
    private var dressedForHintID: String?

    /// When set, every suggestion is built around this item ("Outfits with this").
    let anchor: Item?
    private let generator: OutfitGenerator
    private let weatherService: any WeatherProviding
    private let outfitStylist: any OutfitStylist
    private let calendar: any CalendarReading

    init(
        generator: OutfitGenerator,
        weatherService: any WeatherProviding,
        stylist: any OutfitStylist,
        calendar: any CalendarReading,
        anchor: Item? = nil
    ) {
        self.anchor = anchor
        self.generator = generator
        self.weatherService = weatherService
        outfitStylist = stylist
        self.calendar = calendar
    }

    func context(profile: StyleProfile? = nil, date: Date = .now) -> OutfitContext {
        OutfitContext(
            occasion: occasion,
            weather: Weather(
                feelsLikeC: feelsLikeC,
                precipitationChance: isRainy ? Self.rainyChance : 0,
                dayRange: feelsLikeC == forecastNowC ? forecastRange : nil
            ),
            date: date,
            profile: profile,
            palette: palette
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
        suggestions = found.filter { !dismissed.contains($0.id) }
        stylist = .idle
    }

    // MARK: Reactions

    /// ♥ saves the outfit and teaches the engine you like these pairings; tapping again takes both back.
    func toggleSaved(_ outfit: ScoredOutfit, isSaved: Bool, recorder: FeedbackRecorder) {
        if isSaved {
            recorder.removeSavedOutfit(id: outfit.id)
            recorder.revert(.liked, for: outfit.outfit)
            toast = Toast(symbol: "heart.slash", message: "Removed from saved")
        } else {
            recorder.saveOutfit(outfit.outfit, occasion: occasion)
            recorder.record(.liked, for: outfit.outfit)
            toast = Toast(symbol: "heart.fill", message: "Saved. You'll see more like this.")
        }
    }

    /// ✕ hides the outfit and teaches the engine to avoid these pairings, with an undo.
    func dismiss(_ outfit: ScoredOutfit, recorder: FeedbackRecorder) {
        guard let index = suggestions.firstIndex(of: outfit) else { return }
        suggestions.remove(at: index)
        dismissed.insert(outfit.id)
        recorder.record(.disliked, for: outfit.outfit)
        toast = Toast(symbol: "eye.slash", message: "Hidden. You'll see fewer like this.") { [weak self] in
            guard let self else { return }
            dismissed.remove(outfit.id)
            suggestions.insert(outfit, at: min(index, suggestions.count))
            recorder.revert(.disliked, for: outfit.outfit)
        }
    }

    /// "Wear this" logs the outfit as today's, so its pieces rest for a few days; tapping again takes it back.
    func toggleWorn(_ outfit: ScoredOutfit, recorder: FeedbackRecorder, now: Date = .now) {
        if let entry = recorder.wearEntry(for: outfit.id, on: now) {
            unwear(entry, recorder: recorder)
            return
        }
        let entry = recorder.wear(outfit.outfit, occasion: occasion, on: now)
        toast = Toast(symbol: "checkmark.circle.fill", message: "Today's outfit. Find it in Saved → Worn.") {
            recorder.unwear(entry)
        }
    }

    func unwear(_ entry: WearEntry, recorder: FeedbackRecorder) {
        recorder.unwear(entry)
        toast = Toast(symbol: "arrow.uturn.backward", message: "No longer today's outfit")
    }

    // MARK: Swap one piece

    /// Versions of an outfit with one piece changed, for today's occasion and weather.
    func swaps(replacing piece: Item, in outfit: Outfit, closet: [Item], profile: StyleProfile) -> [ScoredOutfit] {
        generator.swaps(replacing: piece, in: outfit, from: closet, context: context(profile: profile))
    }

    /// Puts a swapped version where the suggestion was.
    func replace(_ original: Outfit, with swapped: ScoredOutfit) {
        guard let index = suggestions.firstIndex(where: { $0.id == original.id }) else { return }
        suggestions[index] = swapped
        toast = Toast(symbol: "arrow.triangle.2.circlepath", message: "Swapped")
    }

    // MARK: Weather

    /// Fills temperature and rain from the forecast for the user's location. Manual edits still win afterwards.
    func loadWeather() async {
        weather = .loading
        do {
            let forecast = try await weatherService.forecastHere()
            feelsLikeC = forecast.feelsLikeNowC.rounded().clamped(to: Self.temperatureRange)
            forecastNowC = feelsLikeC
            let (low, high) = (forecast.feelsLikeMinC, forecast.feelsLikeMaxC)
            forecastRange = min(low, high) ... max(low, high)
            isRainy = Weather(feelsLikeC: forecast.feelsLikeNowC, precipitationChance: forecast.precipitationChance)
                .isRainy
            weather = .loaded(forecast)
        } catch {
            weather = .failed((error as? WeatherError)?.userMessage ?? WeatherError.unavailable.userMessage)
        }
    }

    // MARK: Calendar

    /// Reads the rest of today's events for ones worth dressing for. Never prompts; `connectCalendar` does.
    func loadCalendarHints(now: Date = .now, calendar dates: Calendar = .current) async {
        switch calendar.access {
        case .notAsked:
            calendarHints = .notAsked
        case .denied:
            calendarHints = .unavailable
        case .granted:
            let endOfDay = dates.date(byAdding: .day, value: 1, to: dates.startOfDay(for: now)) ?? now
            calendarHints = await .hints(OccasionHint.hints(from: calendar.events(from: now, to: endOfDay)))
        }
    }

    func connectCalendar(now: Date = .now) async {
        _ = await calendar.requestAccess()
        await loadCalendarHints(now: now)
    }

    /// Switches the occasion to what an event calls for.
    func dress(for hint: CalendarHint) {
        dressedForHintID = hint.id
        occasion = hint.occasion
        toast = Toast(symbol: "calendar", message: "Dressing for \(hint.title)")
    }

    /// True for the event last dressed for, while its occasion is still the one chosen.
    func isDressing(for hint: CalendarHint) -> Bool {
        dressedForHintID == hint.id && occasion == hint.occasion
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
