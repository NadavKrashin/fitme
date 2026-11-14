import FitEngine
import Foundation
import SwiftData
import Testing
@testable import FitMe

@MainActor
struct TodayModelTests {
    let closet = try! DemoCloset.items()
    let container = try! Persistence.makeInMemoryContainer()

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
        let sweater = try #require(closet.first { $0.id == "t13" })
        let model = makeTodayModel(anchor: sweater)
        model.feelsLikeC = 12

        await model.refresh(closet: closet, profile: StyleProfile())

        #expect(!model.suggestions.isEmpty)
        #expect(model.suggestions.allSatisfy { $0.outfit.contains(sweater) })
    }

    private func modelWithSuggestions() async throws -> (TodayModel, FeedbackRecorder) {
        let model = makeTodayModel()
        await model.refresh(closet: closet, profile: StyleProfile())
        try #require(model.suggestions.count >= 2)
        return (model, FeedbackRecorder(context: container.mainContext))
    }

    /// Regression: liking an outfit used to overwrite "worn", so "Wear this" came back.
    @Test func savingKeepsTheOutfitWorn() async throws {
        let (model, recorder) = try await modelWithSuggestions()
        let outfit = model.suggestions[0]

        model.toggleWorn(outfit, recorder: recorder)
        model.toggleSaved(outfit, isSaved: false, recorder: recorder)

        #expect(recorder.wearEntry(for: outfit.id) != nil)
    }

    @Test func dismissingHidesWithAnUndoThatRestoresIt() async throws {
        let (model, recorder) = try await modelWithSuggestions()
        let outfit = model.suggestions[1]

        model.dismiss(outfit, recorder: recorder)

        #expect(!model.suggestions.contains(outfit))
        #expect(recorder.profile().affinityScore(outfit.outfit.coreItems) < 0.5)
        let undo = try #require(model.toast?.undo, "dismissing offers an undo")

        undo()

        #expect(model.suggestions[1] == outfit, "back in its old place")
        #expect(recorder.profile().affinityScore(outfit.outfit.coreItems) == 0.5)
        await model.refresh(closet: closet, profile: recorder.profile())
        #expect(model.suggestions.contains(outfit), "no longer hidden after undo")
    }

    @Test func savingStoresTheOutfitAndUnsavingRemovesIt() async throws {
        let (model, recorder) = try await modelWithSuggestions()
        let outfit = model.suggestions[0]

        model.toggleSaved(outfit, isSaved: false, recorder: recorder)
        let saved = try container.mainContext.fetch(FetchDescriptor<SavedOutfit>())
        #expect(saved.map(\.outfitID) == [outfit.id])
        #expect(saved.first?.occasion == model.occasion)
        #expect(model.toast?.message.hasPrefix("Saved") == true)
        #expect(recorder.profile().affinityScore(outfit.outfit.coreItems) > 0.5)

        model.toggleSaved(outfit, isSaved: true, recorder: recorder)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SavedOutfit>()) == 0)
        #expect(recorder.profile().affinityScore(outfit.outfit.coreItems) == 0.5)
    }

    /// "Wear this" logs today's outfit; tapping it again takes the wear back, as the Undo does.
    @Test func wearingAgainTakesItBack() async throws {
        let (model, recorder) = try await modelWithSuggestions()
        let outfit = model.suggestions[0]
        for item in outfit.outfit.items {
            container.mainContext.insert(ItemRecord(item: item))
        }

        model.toggleWorn(outfit, recorder: recorder)
        var records = try container.mainContext.fetch(FetchDescriptor<ItemRecord>())
        #expect(records.allSatisfy { $0.wearCount == 1 && $0.lastWorn != nil })
        #expect(try container.mainContext.fetchCount(FetchDescriptor<WearEntry>()) == 1)

        model.toggleWorn(outfit, recorder: recorder)
        records = try container.mainContext.fetch(FetchDescriptor<ItemRecord>())
        #expect(records.allSatisfy { $0.wearCount == 0 && $0.lastWorn == nil })
        #expect(try container.mainContext.fetchCount(FetchDescriptor<WearEntry>()) == 0)
        #expect(recorder.profile().isEmpty)
    }

    @Test func wearingOffersAnUndo() async throws {
        let (model, recorder) = try await modelWithSuggestions()
        let outfit = model.suggestions[0]

        model.toggleWorn(outfit, recorder: recorder)
        let undo = try #require(model.toast?.undo)
        undo()

        #expect(recorder.wearEntry(for: outfit.id) == nil)
    }

    /// "Swap" in an outfit's pieces replaces the suggestion where it was, so the list doesn't jump.
    @Test func aSwapReplacesTheSuggestionInPlace() async throws {
        let (model, _) = try await modelWithSuggestions()
        let original = model.suggestions[1]
        let shoes = try #require(original.outfit.shoes)
        let swapped = try #require(
            model.swaps(replacing: shoes, in: original.outfit, closet: closet, profile: StyleProfile()).first
        )

        model.replace(original.outfit, with: swapped)

        #expect(model.suggestions[1] == swapped)
        #expect(model.suggestions[1].outfit.shoes != shoes)
        #expect(model.toast?.message == "Swapped")
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

    @Test func colorMoodReachesTheEngine() {
        let model = makeTodayModel()
        #expect(model.context().palette == .balanced)
        model.palette = .neutral
        #expect(model.context().palette == .neutral)
    }
}
