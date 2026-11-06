import FitEngine
import Foundation
import SwiftData

/// The single stored `StyleProfile`. Kept as encoded JSON: its dictionary of pair affinities isn't a shape SwiftData
/// stores reliably as a composite attribute.
@Model
final class StyleProfileRecord {
    private var profileData: Data
    var updatedAt: Date

    init(profile: StyleProfile = StyleProfile(), updatedAt: Date = .now) {
        profileData = (try? JSONEncoder().encode(profile)) ?? Data()
        self.updatedAt = updatedAt
    }

    var profile: StyleProfile {
        get { (try? JSONDecoder().decode(StyleProfile.self, from: profileData)) ?? StyleProfile() }
        set {
            profileData = (try? JSONEncoder().encode(newValue)) ?? profileData
            updatedAt = .now
        }
    }
}
