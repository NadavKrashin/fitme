import FitEngine
import Foundation
import SwiftData
import Testing
@testable import FitMe

@MainActor
struct TodayModelTests {
    let closet = try! DemoCloset.items()

    @Test func suggestsValidOutfitsForTheChosenOccasion() async {
        let model = makeTodayModel()
        model.occasion = .formal

        await model.refresh(closet: closet, profile: StyleProfile())

        #expect(!model.suggestions.isEmpty)
        #expect(model.suggestions.count <= 5)
        for suggestion in model.suggestions {
            #expect(Rules.isValid(suggestion.outfit, context: model.context()))
        }
    }

    @Test func emptyClosetGivesNoSuggestions() async {
        let model = makeTodayModel()
        await model.refresh(closet: [], profile: StyleProfile())
        #expect(model.suggestions.isEmpty)
    }

    @Test func anchoredSuggestionsAllIncludeTheItem() async throws {
        let sweater = try #require(closet.first { $0.id == "t18" })
        let model = makeTodayModel(anchor: sweater)
        model.feelsLikeC = 12

        await model.refresh(closet: closet, profile: StyleProfile())

        #expect(!model.suggestions.isEmpty)
        #expect(model.suggestions.allSatisfy { $0.outfit.contains(sweater) })
    }

    @Test func dislikedOutfitDisappearsAndIsRemembered() async throws {
        let container = try Persistence.makeInMemoryContainer()
        let recorder = FeedbackRecorder(context: container.mainContext)
        let model = makeTodayModel()
        await model.refresh(closet: closet, profile: StyleProfile())
        let disliked = try #require(model.suggestions.first)

        model.react(.disliked, to: disliked, recorder: recorder)

        #expect(!model.suggestions.contains(disliked))
        #expect(model.feedback[disliked.id] == .disliked)
        #expect(recorder.profile().affinityScore(disliked.outfit.coreItems) < 0.5)

        await model.refresh(closet: closet, profile: recorder.profile())
        #expect(!model.suggestions.contains(disliked), "stays hidden for the session")
    }

    @Test func weatherFillsTemperatureAndRain() async {
        let model = makeTodayModel()
        await model.loadWeather()

        #expect(model.feelsLikeC == 9)
        #expect(model.isRainy)
        guard case .loaded = model.weather else {
            Issue.record("expected loaded weather, got \(model.weather)")
            return
        }
    }

    @Test func weatherFailureKeepsManualValues() async {
        let model = makeTodayModel(weather: FakeWeather(result: .failure(.locationDenied)))
        model.feelsLikeC = 25

        await model.loadWeather()

        #expect(model.feelsLikeC == 25)
        #expect(model.weather == .failed(WeatherError.locationDenied.userMessage))
    }

    @Test func stylistPicksComeFromTheCandidates() async throws {
        let model = makeTodayModel()
        await model.askStylist(closet: closet, profile: StyleProfile())

        guard case let .picked(picks) = model.stylist else {
            Issue.record("expected picks, got \(model.stylist)")
            return
        }
        let pick = try #require(picks.first)
        #expect(Rules.isValid(pick.outfit.outfit, context: model.context()))
    }

    @Test func stylistErrorsAreExplained() async {
        let model = makeTodayModel(stylist: FakeStylist(error: ClaudeError.missingAPIKey))
        await model.askStylist(closet: closet, profile: StyleProfile())
        #expect(model.stylist == .failed(ClaudeError.missingAPIKey.userMessage))
    }

    @Test func rainToggleRaisesChanceOfRain() {
        let model = makeTodayModel()
        model.isRainy = true
        #expect(model.context().weather.isRainy)
    }
}
