import FitEngine
import Foundation

/// One city on a trip and how many nights are spent there.
struct TripStop: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var place: Place
    var nights: Int
}

enum Laundry: String, Codable, CaseIterable, Sendable {
    case none, everyThreeDays, everyFiveDays, weekly

    var everyNDays: Int? {
        switch self {
        case .none: nil
        case .everyThreeDays: 3
        case .everyFiveDays: 5
        case .weekly: 7
        }
    }
}

enum Luggage: String, Codable, CaseIterable, Sendable {
    case carryOn, checked
}

/// What one day of the trip holds, and the weather to dress for.
struct TripDayPlan: Codable, Hashable, Sendable {
    var date: Date
    var stopID: UUID
    /// In order, e.g. sightseeing then dinner. Never empty.
    var occasions: [Occasion]
    var weather: DailyWeather
}

/// The outfit planned for one occasion on one day.
struct PlannedOutfit: Codable, Hashable, Sendable {
    var dayIndex: Int
    var occasion: Occasion
    /// Empty when nothing packed suits this slot.
    var itemIDs: [String]
    /// True when the bag is too small to keep this outfit fresh: it repeats a top before the next wash.
    var repeatsAPiece = false
    /// Set in trip mode when the user wears it.
    var wornOn: Date?

    var isCovered: Bool {
        !itemIDs.isEmpty
    }
}

extension PlannedOutfit {
    private enum CodingKeys: String, CodingKey {
        case dayIndex, occasion, itemIDs, wornOn, repeatsAPiece
    }

    /// Trips are stored as JSON, so fields added later decode with their defaults from older trips.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayIndex = try container.decode(Int.self, forKey: .dayIndex)
        occasion = try container.decode(Occasion.self, forKey: .occasion)
        itemIDs = try container.decode([String].self, forKey: .itemIDs)
        wornOn = try container.decodeIfPresent(Date.self, forKey: .wornOn)
        repeatsAPiece = try container.decodeIfPresent(Bool.self, forKey: .repeatsAPiece) ?? false
    }
}

/// After the trip: what actually got worn.
struct TripDebrief: Codable, Hashable, Sendable {
    var wornItemIDs: Set<String>
    var completedAt: Date
}

/// Everything about a trip: the plan the user made, and the bag FitMe packed for it.
struct TripDetails: Codable, Hashable, Sendable {
    var startDate: Date
    var stops: [TripStop]
    var laundry: Laundry = .none
    var luggage: Luggage = .checked
    var days: [TripDayPlan] = []

    var packedItemIDs: [String] = []
    var outfits: [PlannedOutfit] = []
    /// Distinct good outfits the packed items make.
    var outfitCount = 0
    /// Packing-list entries already in the bag: item ids and essential names.
    var checkedOff: Set<String> = []
    var debrief: TripDebrief?

    var endDate: Date {
        days.last?.date ?? startDate
    }

    var name: String {
        let names = stops.map(\.place.name)
        switch names.count {
        case 0: return "New trip"
        case 1, 2: return names.joined(separator: " & ")
        default: return "\(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }

    /// The trip's dates and stops: one day per night plus the day home. Each day belongs to the stop where that
    /// night is spent; the last day to the last stop. A day keeps its occasions while it stays at the same stop, and
    /// its weather while its date is unchanged.
    func laidOut(calendar: Calendar = .current) -> TripDetails {
        var copy = self
        let start = calendar.startOfDay(for: startDate)
        let stopByDay = stops.flatMap { Array(repeating: $0.id, count: max($0.nights, 1)) }
        let dayCount = stopByDay.count + 1
        copy.startDate = start
        copy.days = (0 ..< dayCount).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: start),
                  let stopID = stopByDay[safe: index] ?? stops.last?.id
            else { return nil }
            let isTravelDay = index == 0 || index == dayCount - 1 || stopByDay[safe: index - 1] != stopID
            var day = TripDayPlan(
                date: date,
                stopID: stopID,
                occasions: isTravelDay ? [.travel] : [.casual],
                weather: .unknown
            )
            if let old = days[safe: index], old.stopID == stopID {
                day.occasions = old.occasions
                if old.date == date {
                    day.weather = old.weather
                }
            }
            return day
        }
        return copy
    }

    /// Where the trip is relative to `now`.
    func phase(now: Date = .now, calendar: Calendar = .current) -> Phase {
        let today = calendar.startOfDay(for: now)
        if today < calendar.startOfDay(for: startDate) {
            return .upcoming
        }
        return today > calendar.startOfDay(for: endDate) ? .finished : .ongoing
    }

    enum Phase {
        case upcoming, ongoing, finished
    }

    /// The day index of `now` while the trip is on.
    func dayIndex(of now: Date = .now, calendar: Calendar = .current) -> Int? {
        let today = calendar.startOfDay(for: now)
        return days.firstIndex { calendar.isDate($0.date, inSameDayAs: today) }
    }

    func stop(forDay index: Int) -> TripStop? {
        days[safe: index].flatMap { day in stops.first { $0.id == day.stopID } }
    }

    /// The indices of the days spent at `stop`.
    func dayIndices(at stop: TripStop) -> [Int] {
        days.indices.filter { days[$0].stopID == stop.id }
    }

    /// Items worn per the plan so far (the starting point of the debrief).
    var plannedWornItemIDs: Set<String> {
        Set(outfits.filter { $0.wornOn != nil }.flatMap(\.itemIDs))
    }

    /// Packed items that came home unworn, once the debrief is done.
    var packedUnwornItemIDs: Set<String> {
        guard let debrief else { return [] }
        return Set(packedItemIDs).subtracting(debrief.wornItemIDs)
    }
}
