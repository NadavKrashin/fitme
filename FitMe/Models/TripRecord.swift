import Foundation
import SwiftData

/// A stored trip. The plan is kept as encoded JSON (nested arrays of value types aren't a shape SwiftData stores
/// reliably); the dates are mirrored as columns so trips can be sorted.
@Model
final class TripRecord {
    @Attribute(.unique) var tripID: UUID
    var name: String
    var startDate: Date
    var endDate: Date
    var createdAt: Date
    private var detailsData: Data

    init(details: TripDetails, tripID: UUID = UUID(), createdAt: Date = .now) {
        self.tripID = tripID
        name = details.name
        startDate = details.startDate
        endDate = details.endDate
        self.createdAt = createdAt
        detailsData = (try? JSONEncoder().encode(details)) ?? Data()
    }

    var details: TripDetails {
        get {
            (try? JSONDecoder().decode(TripDetails.self, from: detailsData))
                ?? TripDetails(startDate: startDate, stops: [])
        }
        set {
            detailsData = (try? JSONEncoder().encode(newValue)) ?? detailsData
            name = newValue.name
            startDate = newValue.startDate
            endDate = newValue.endDate
        }
    }
}
