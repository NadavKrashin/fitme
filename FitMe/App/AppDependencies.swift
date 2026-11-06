import FitEngine
import SwiftUI

/// Services the app needs, created once at launch and handed to features through the SwiftUI environment.
/// Previews and tests build their own with fakes.
struct AppDependencies: Sendable {
    let secrets: any SecretStore
    let outfitGenerator: OutfitGenerator
    let photoProcessor: any PhotoProcessing
    let tagger: any TaggingService
    let thumbnails: ThumbnailCache

    static func live() -> AppDependencies {
        let secrets = KeychainSecretStore(service: Bundle.main.bundleIdentifier ?? "FitMe")
        let claude = ClaudeClient(apiKey: { try secrets.read(.claudeAPIKey) }, transport: URLSession.shared)
        return AppDependencies(
            secrets: secrets,
            outfitGenerator: OutfitGenerator(),
            photoProcessor: ImagePipeline(),
            tagger: ClaudeTaggingService(client: claude),
            thumbnails: ThumbnailCache()
        )
    }

    #if DEBUG
    static func preview() -> AppDependencies {
        AppDependencies(
            secrets: InMemorySecretStore(),
            outfitGenerator: OutfitGenerator(),
            photoProcessor: ImagePipeline(),
            tagger: PreviewTaggingService(),
            thumbnails: ThumbnailCache()
        )
    }
    #endif
}

extension EnvironmentValues {
    @Entry var dependencies = AppDependencies.live()
}
