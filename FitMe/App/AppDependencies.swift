import FitEngine
import SwiftUI

/// Services the app needs, created once at launch and handed to features through the SwiftUI environment.
/// Previews and tests build their own with fakes.
struct AppDependencies: Sendable {
    let secrets: any SecretStore
    let outfitGenerator: OutfitGenerator

    static func live() -> AppDependencies {
        AppDependencies(
            secrets: KeychainSecretStore(service: Bundle.main.bundleIdentifier ?? "FitMe"),
            outfitGenerator: OutfitGenerator()
        )
    }

    static func preview() -> AppDependencies {
        AppDependencies(secrets: InMemorySecretStore(), outfitGenerator: OutfitGenerator())
    }
}

extension EnvironmentValues {
    @Entry var dependencies = AppDependencies.live()
}
