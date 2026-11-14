import Observation

enum AppTab: Hashable {
    case today, trips, saved, closet, settings
}

/// Where new clothes come from.
enum AddSource: Sendable {
    case camera
    case library
}

/// The selected tab, and requests that cross tabs: onboarding and empty screens ask Closet to open the camera or the
/// photo library.
@MainActor
@Observable
final class AppNavigation {
    var tab: AppTab = .today
    /// Closet opens this and clears it.
    var addRequest: AddSource?

    func addClothes(_ source: AddSource) {
        tab = .closet
        addRequest = source
    }
}
