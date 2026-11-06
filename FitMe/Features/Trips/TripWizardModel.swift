import FitEngine
import Foundation
import Observation
import os
import SwiftData

/// The new-trip (or edit-trip) flow: stops and dates, then each day's plans, then packing.
@MainActor
@Observable
final class TripWizardModel {
    enum WeatherState: Equatable {
        case idle
        case loading
        case loaded
        /// Some or all stops have no weather; their days use mild defaults.
        case failed(String)
    }

    static let defaultNights = 3
    static let maxNightsPerStop = 30

    var details: TripDetails
    private(set) var weather: WeatherState = .idle
    private(set) var isPacking = false

    /// The trip being edited, if any.
    let existing: TripRecord?
    private let weatherService: any TripWeatherProviding
    private let planner: TripPlanner

    init(existing: TripRecord? = nil, weatherService: any TripWeatherProviding, planner: TripPlanner) {
        self.existing = existing
        self.weatherService = weatherService
        self.planner = planner
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
        details = existing?.details ?? TripDetails(startDate: tomorrow ?? .now, stops: [])
    }

    var canContinue: Bool {
        !details.stops.isEmpty
    }

    // MARK: Stops

    func addStop(_ place: Place) {
        details.stops.append(TripStop(place: place, nights: Self.defaultNights))
    }

    func removeStops(at offsets: IndexSet) {
        details.stops.remove(atOffsets: offsets)
    }

    // MARK: Days

    /// Turns stops and dates into days, keeping plans that still apply, then fetches weather for new days.
    func layOutDays() async {
        details = details.laidOut()
        await loadWeather()
    }

    func toggle(_ occasion: Occasion, onDay index: Int) {
        guard details.days.indices.contains(index) else { return }
        var occasions = details.days[index].occasions
        if let position = occasions.firstIndex(of: occasion) {
            guard occasions.count > 1 else { return } // every day needs something to dress for
            occasions.remove(at: position)
        } else {
            occasions.append(occasion)
            occasions.sort { Occasion.allCases.firstIndex(of: $0) ?? 0 < Occasion.allCases.firstIndex(of: $1) ?? 0 }
        }
        details.days[index].occasions = occasions
    }

    /// Fetches weather for each stop's days that don't have it yet.
    func loadWeather() async {
        weather = .loading
        var failedPlaces: [String] = []
        for stop in details.stops {
            let indices = details.dayIndices(at: stop).filter { details.days[$0].weather == .unknown }
            guard !indices.isEmpty else { continue }
            do {
                let forecast = try await weatherService.dailyWeather(
                    at: stop.place,
                    days: indices.map { details.days[$0].date }
                )
                for (index, day) in zip(indices, forecast) {
                    details.days[index].weather = day
                }
            } catch {
                failedPlaces.append(stop.place.name)
            }
        }
        weather = failedPlaces.isEmpty
            ? .loaded
            :
            .failed(
                "Couldn't get the weather for \(failedPlaces.joined(separator: " and ")). Planning for mild days."
            )
    }

    // MARK: Packing

    /// Packs the bag and stores the trip. Returns the saved record.
    func pack(closet: [Item], context: ModelContext) async -> TripRecord {
        isPacking = true
        defer { isPacking = false }
        let profile = FeedbackRecorder(context: context).profile()
        let pastTrips = ((try? context.fetch(FetchDescriptor<TripRecord>())) ?? [])
            .filter { $0.tripID != existing?.tripID }
            .map(\.details)
        let packed = await planner.pack(
            details,
            closet: closet,
            profile: profile,
            packedUnworn: TripPlanner.packedUnworn(from: pastTrips)
        )
        let record: TripRecord
        if let existing {
            existing.details = packed
            record = existing
        } else {
            record = TripRecord(details: packed)
            context.insert(record)
        }
        do {
            try context.save()
        } catch {
            Logger.trips.error("Couldn't save the trip: \(String(describing: error))")
        }
        return record
    }
}
