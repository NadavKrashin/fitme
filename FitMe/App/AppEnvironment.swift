import Foundation
import SwiftData

/// The deployment environment this build belongs to, fixed at compile time by the build configuration.
///
/// Debug and Staging builds define `STAGING`; Release builds don't. Apart from the `DemoData` folder and the
/// one place that shows its settings section, this is the only code that reads that condition.
enum AppEnvironment: String, Sendable {
    case staging
    case production

    #if STAGING
    static let current = AppEnvironment.staging
    #else
    static let current = AppEnvironment.production
    #endif

    var displayName: String {
        switch self {
        case .staging: "Staging"
        case .production: "Production"
        }
    }

    /// App Store screenshot mode (`-FitMeScreenshots`, Staging only; see `ScreenshotStage`): loads the demo closet
    /// and a packed sample trip, and returns services with steady weather and an empty calendar. Release builds
    /// return `dependencies` unchanged.
    @MainActor
    static func stagingScreenshots(_ dependencies: AppDependencies, container: ModelContainer) -> AppDependencies {
        #if STAGING
        guard ScreenshotStage.isActive else { return dependencies }
        ScreenshotStage.loadCloset(into: container.mainContext)
        Task { await ScreenshotStage.packSampleTrip(into: container.mainContext) }
        return ScreenshotStage.dependencies(dependencies)
        #else
        return dependencies
        #endif
    }

    /// FitMe's Claude proxy for this build (`FITME_PROXY_URL` in project.yml), or nil when none is configured yet.
    static var proxyURL: URL? {
        guard let text = Bundle.main.infoDictionary?["FitMeProxyURL"] as? String, !text.isEmpty else { return nil }
        return URL(string: text)
    }

    /// "0.1.0 (42)": marketing version and CI build number.
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
