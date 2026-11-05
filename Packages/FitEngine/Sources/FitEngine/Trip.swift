import Foundation

public struct TripDay: Codable, Hashable, Sendable {
    public var date: Date
    public var weather: Weather
    /// What the day holds, in order (e.g. sightseeing, then dinner).
    public var occasions: [Occasion]

    public init(date: Date, weather: Weather, occasions: [Occasion]) {
        self.date = date
        self.weather = weather
        self.occasions = occasions
    }
}

public struct PackingOptions: Hashable, Sendable {
    public var maxShoes = 3
    public var maxOuterwear = 2
    public var maxItems: Int?
    /// Minimum score for an outfit to count as "good enough to plan a day around".
    public var scoreThreshold = 62.0
    /// Wash every N days; nil means no laundry during the trip.
    public var laundryEveryNDays: Int?
    /// Tops and one-pieces are worn once per laundry cycle; bottoms can repeat up to this many times.
    public var maxWearsPerBottom = 3

    public init() {}
}

/// One outfit slot on one day of the trip.
public struct SlotAssignment: Hashable, Sendable {
    public var dayIndex: Int
    public var date: Date
    public var occasion: Occasion
    public var outfit: ScoredOutfit?
    /// True when the only option repeats a piece beyond the wear limits.
    public var exceedsWearLimit: Bool
}

public struct PackingResult: Sendable {
    public var items: [Item]
    public var assignments: [SlotAssignment]
    /// Distinct good outfits the packed items make across the whole trip.
    public var outfitCount: Int

    public var uncovered: [SlotAssignment] {
        assignments.filter { $0.outfit == nil }
    }

    public var summary: String {
        let covered = assignments.count - uncovered.count
        return "\(items.count) items → \(outfitCount) outfits → \(covered)/\(assignments.count) slots covered"
    }
}

public struct EssentialItem: Hashable, Sendable {
    public let name: String
    public let count: Int
}

/// Non-clothing basics, counted from trip length and laundry.
public enum Essentials {
    public static func checklist(
        days: Int,
        laundryEveryNDays: Int? = nil,
        occasions: Set<Occasion> = []
    ) -> [EssentialItem] {
        // One per day until the next wash, plus a spare.
        let perCycle = min(days, laundryEveryNDays ?? days) + 1
        var list = [
            EssentialItem(name: "Underwear", count: perCycle),
            EssentialItem(name: "Socks", count: perCycle),
            EssentialItem(name: "Sleepwear", count: 1),
        ]
        if occasions.contains(.beach) {
            list.append(EssentialItem(name: "Swimwear", count: 1))
        }
        if occasions.contains(.sport) {
            list.append(EssentialItem(name: "Sports socks", count: min(days, 3)))
        }
        return list
    }
}
