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
    /// Calendar events that set a day's occasions, by the day they fall on.
    private(set) var calendarHints: [Date: [CalendarHint]] = [:]

    /// The trip being edited, if any.
    let existing: TripRecord?
    private let weatherService: any TripWeatherProviding
    private let planner: TripPlanner
    private let calendar: any CalendarReading
    private let dates: Calendar
    /// Days already given their calendar occasions, so a removed one isn't added back on the next layout.
    private var hintedDays: Set<Date>

    init(
        existing: TripRecord? = nil,
        weatherService: any TripWeatherProviding,
        planner: TripPlanner,
        calendar: any CalendarReading,
        dates: Calendar = .current
    ) {
        self.existing = existing
        self.weatherService = weatherService
        self.planner = planner
        self.calendar = calendar
        self.dates = dates
        let tomorrow = dates.date(byAdding: .day, value: 1, to: dates.startOfDay(for: .now))
        let details = existing?.details ?? TripDetails(startDate: tomorrow ?? .now, stops: [])
        self.details = details
        // An existing trip's days were planned already.
        hintedDays = Set(details.days.map { dates.startOfDay(for: $0.date) })
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

    /// Turns stops and dates into days, keeping plans that still apply, adds what the calendar says about new days,
    /// then fetches weather for new days.
    func layOutDays() async {
        details = details.laidOut(calendar: dates)
        await addCalendarOccasions()
        await loadWeather()
    }

    func toggle(_ occasion: Occasion, onDay index: Int) {
        guard details.days.indices.contains(index) else { return }
        var occasions = details.days[index].occasions
        if let position = occasions.firstIndex(of: occasion) {
            guard occasions.count > 1 else { return } // every day needs something to dress for
            occasions.remove(at: position)
        } else {
            occasions = Self.inOrder(occasions + [occasion])
        }
        details.days[index].occasions = occasions
    }

    /// Adds the occasions the calendar calls for (a wedding, a client dinner) to days not planned before. Only reads
    /// the calendar if access was already given on Today; the wizard never asks.
    private func addCalendarOccasions() async {
        let newDays = details.days.indices.filter { !hintedDays.contains(dates.startOfDay(for: details.days[$0].date)) }
        guard calendar.access == .granted, let first = newDays.first, let last = newDays.last,
              let end = dates.date(byAdding: .day, value: 1, to: dates.startOfDay(for: details.days[last].date))
        else { return }
        let events = await calendar.events(from: dates.startOfDay(for: details.days[first].date), to: end)
        let hints = events.compactMap { event in
            OccasionHint.occasion(for: event.title).map {
                CalendarHint(title: event.title, start: event.start, isAllDay: event.isAllDay, occasion: $0)
            }
        }
        for index in newDays {
            let day = dates.startOfDay(for: details.days[index].date)
            let onDay = hints.filter { dates.isDate($0.start, inSameDayAs: day) }
            hintedDays.insert(day)
            guard !onDay.isEmpty else { continue }
            calendarHints[day] = onDay
            details.days[index].occasions = Self.inOrder(details.days[index].occasions + onDay.map(\.occasion))
        }
    }

    /// The calendar events behind a day's occasions, if any.
    func hints(onDay index: Int) -> [CalendarHint] {
        details.days[safe: index].flatMap { calendarHints[dates.startOfDay(for: $0.date)] } ?? []
    }

    /// Unique, in the order the chips show them.
    private static func inOrder(_ occasions: [Occasion]) -> [Occasion] {
        Occasion.allCases.filter(occasions.contains)
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
