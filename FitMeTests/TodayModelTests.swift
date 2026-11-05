import FitEngine
import Testing
@testable import FitMe

@MainActor
struct TodayModelTests {
    @Test func suggestsDifferentOutfitsForTheChosenOccasion() async throws {
        let model = TodayModel(generator: OutfitGenerator())
        model.occasion = .formal

        try await model.refresh(closet: DemoCloset.items())

        #expect(!model.suggestions.isEmpty)
        #expect(model.suggestions.count <= 5)
        for suggestion in model.suggestions {
            #expect(Rules.isValid(suggestion.outfit, context: model.context))
        }
    }

    @Test func emptyClosetGivesNoSuggestions() async {
        let model = TodayModel(generator: OutfitGenerator())
        await model.refresh(closet: [])
        #expect(model.suggestions.isEmpty)
    }

    @Test func rainToggleRaisesChanceOfRain() {
        let model = TodayModel(generator: OutfitGenerator())
        model.isRainy = true
        #expect(model.context.weather.isRainy)
    }
}
