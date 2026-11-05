import Foundation

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

    /// "0.1.0 (42)": marketing version and CI build number.
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
