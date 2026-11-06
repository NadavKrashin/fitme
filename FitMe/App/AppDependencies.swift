import FitEngine
import SwiftData
import SwiftUI

/// Services the app needs, created once at launch and handed to features through the SwiftUI environment.
/// Previews and tests build their own with fakes.
struct AppDependencies: Sendable {
    let secrets: any SecretStore
    let outfitGenerator: OutfitGenerator
    let photoProcessor: any PhotoProcessing
    let tagger: any TaggingService
    let weather: any WeatherProviding
    let stylist: any OutfitStylist
    let places: any PlaceSearching
    let tripWeather: any TripWeatherProviding
    let capsuleReviewer: any CapsuleReviewing
    let tripPlanner: TripPlanner
    let thumbnails: ThumbnailCache

    static func live() -> AppDependencies {
        let secrets = KeychainSecretStore(service: Bundle.main.bundleIdentifier ?? "FitMe")
        let claude = ClaudeClient(apiKey: { try secrets.read(.claudeAPIKey) }, transport: URLSession.shared)
        let openMeteo = OpenMeteoTripWeather(transport: URLSession.shared)
        return AppDependencies(
            secrets: secrets,
            outfitGenerator: OutfitGenerator(),
            photoProcessor: ImagePipeline(),
            tagger: ClaudeTaggingService(client: claude),
            weather: OpenMeteoWeatherService(locator: CoreLocationLocator(), transport: URLSession.shared),
            stylist: ClaudeStylist(client: claude),
            places: openMeteo,
            tripWeather: openMeteo,
            capsuleReviewer: ClaudeCapsuleReviewer(client: claude),
            tripPlanner: TripPlanner(),
            thumbnails: ThumbnailCache()
        )
    }

    @MainActor
    func makeTodayModel(anchor: Item?) -> TodayModel {
        TodayModel(generator: outfitGenerator, weatherService: weather, stylist: stylist, anchor: anchor)
    }

    @MainActor
    func makeTripWizard(editing trip: TripRecord?) -> TripWizardModel {
        TripWizardModel(existing: trip, weatherService: tripWeather, planner: tripPlanner)
    }

    @MainActor
    func makeTripModel(_ trip: TripRecord, context: ModelContext) -> TripModel {
        TripModel(record: trip, planner: tripPlanner, reviewer: capsuleReviewer, context: context)
    }

    #if DEBUG
    static func preview() -> AppDependencies {
        AppDependencies(
            secrets: InMemorySecretStore(),
            outfitGenerator: OutfitGenerator(),
            photoProcessor: ImagePipeline(),
            tagger: PreviewTaggingService(),
            weather: PreviewWeatherService(),
            stylist: PreviewStylist(),
            places: PreviewTripWeather(),
            tripWeather: PreviewTripWeather(),
            capsuleReviewer: PreviewCapsuleReviewer(),
            tripPlanner: TripPlanner(),
            thumbnails: ThumbnailCache()
        )
    }
    #endif
}

extension EnvironmentValues {
    @Entry var dependencies = AppDependencies.live()
}
