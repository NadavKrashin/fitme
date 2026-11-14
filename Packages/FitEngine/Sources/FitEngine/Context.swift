import Foundation

public enum Occasion: String, Codable, CaseIterable, Sendable {
    /// `sport` is a run or the gym; `hike` is outdoors on foot.
    case casual, smartCasual, work, date, formal, sport, hike, beach, travel

    /// Acceptable range for the outfit's average formality.
    public var formalityRange: ClosedRange<Double> {
        switch self {
        case .casual, .travel: return 1 ... 3
        case .smartCasual, .work, .date: return 2.5 ... 4
        case .formal: return 3.75 ... 5
        case .sport, .hike, .beach: return 1 ... 2
        }
    }

    /// The formality the outfit should ideally average.
    public var targetFormality: Double {
        switch self {
        case .casual, .travel: return 2
        case .smartCasual, .work: return 3
        case .date: return 3.3
        case .formal: return 4.5
        case .sport, .hike, .beach: return 1.2
        }
    }

    /// Styles every core item must carry one of: sportswear for a workout, sportswear or outdoor gear for a hike.
    public var requiredStyles: Set<StyleTag> {
        switch self {
        case .sport: [.sporty]
        case .hike: [.outdoor, .sporty]
        default: []
        }
    }
}

public struct Weather: Codable, Hashable, Sendable {
    public var feelsLikeC: Double
    /// Chance of rain, 0...1.
    public var precipitationChance: Double

    public init(feelsLikeC: Double, precipitationChance: Double = 0) {
        self.feelsLikeC = feelsLikeC
        self.precipitationChance = precipitationChance
    }

    public static let mild = Weather(feelsLikeC: 20)

    public var isRainy: Bool {
        precipitationChance >= 0.5
    }

    /// Layers (mid layers, jackets) are only considered when it is cool enough, or when rain calls for a shell.
    public var allowsLayers: Bool {
        feelsLikeC < 22 || isRainy
    }

    /// A jacket over a mid layer (over a shirt) only when it's properly cold; on a mild day one layer is plenty, even
    /// if three light pieces add up to the right warmth.
    public var allowsStackedLayers: Bool {
        feelsLikeC < 14
    }

    /// Target total warmth of the upper-body pieces (top or one-piece + mid layer + outerwear).
    public var upperWarmthTarget: ClosedRange<Int> {
        switch feelsLikeC {
        case 27...: return 1 ... 2
        case 22 ..< 27: return 1 ... 3
        case 17 ..< 22: return 2 ... 5
        case 11 ..< 17: return 4 ... 7
        case 5 ..< 11: return 6 ... 9
        default: return 8 ... 12
        }
    }

    /// The worst case of two forecasts: the colder temperature and the higher chance of rain.
    public func harsher(with other: Weather) -> Weather {
        Weather(
            feelsLikeC: min(feelsLikeC, other.feelsLikeC),
            precipitationChance: max(precipitationChance, other.precipitationChance)
        )
    }

    /// Days in the same band can share outfits when packing.
    public var bandKey: String {
        "\(upperWarmthTarget.lowerBound)\(isRainy ? "r" : "")"
    }
}

/// How much color the user is in the mood for.
public enum Palette: String, Codable, CaseIterable, Sendable {
    /// Neutrals only, unless nothing else works.
    case neutral
    /// Neutrals first; an accent when it earns its place.
    case balanced
    /// An accent color first.
    case colorful
}

/// Everything about "now" that outfit choice depends on.
public struct OutfitContext: Sendable {
    public var occasion: Occasion
    public var weather: Weather
    public var date: Date
    public var profile: StyleProfile?
    public var palette: Palette

    public init(
        occasion: Occasion,
        weather: Weather = .mild,
        date: Date = Date(),
        profile: StyleProfile? = nil,
        palette: Palette = .balanced
    ) {
        self.occasion = occasion
        self.weather = weather
        self.date = date
        self.profile = profile
        self.palette = palette
    }
}
