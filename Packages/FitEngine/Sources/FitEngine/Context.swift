import Foundation

public enum Occasion: String, Codable, CaseIterable {
    case casual, smartCasual, work, date, formal, sport, beach, travel

    /// Acceptable range for the outfit's average formality.
    public var formalityRange: ClosedRange<Double> {
        switch self {
        case .casual, .travel: return 1...3
        case .smartCasual, .work, .date: return 2.5...4
        case .formal: return 3.75...5
        case .sport, .beach: return 1...2
        }
    }

    /// The formality the outfit should ideally average.
    public var targetFormality: Double {
        switch self {
        case .casual, .travel: return 2
        case .smartCasual, .work: return 3
        case .date: return 3.3
        case .formal: return 4.5
        case .sport, .beach: return 1.2
        }
    }

    /// A style every core item must carry (e.g. sportswear for a workout).
    public var requiredStyle: StyleTag? {
        self == .sport ? .sporty : nil
    }
}

public struct Weather: Codable, Hashable {
    public var feelsLikeC: Double
    /// Chance of rain, 0...1.
    public var precipitationChance: Double

    public init(feelsLikeC: Double, precipitationChance: Double = 0) {
        self.feelsLikeC = feelsLikeC
        self.precipitationChance = precipitationChance
    }

    public static let mild = Weather(feelsLikeC: 20)

    public var isRainy: Bool { precipitationChance >= 0.5 }

    /// Layers (mid layers, jackets) are only considered when it is cool enough, or when rain calls for a shell.
    public var allowsLayers: Bool { feelsLikeC < 22 || isRainy }

    /// Target total warmth of the upper-body pieces (top or one-piece + mid layer + outerwear).
    public var upperWarmthTarget: ClosedRange<Int> {
        switch feelsLikeC {
        case 27...: return 1...2
        case 22..<27: return 1...3
        case 17..<22: return 2...5
        case 11..<17: return 4...7
        case 5..<11: return 6...9
        default: return 8...12
        }
    }

    /// Days in the same band can share outfits when packing.
    public var bandKey: String {
        "\(upperWarmthTarget.lowerBound)\(isRainy ? "r" : "")"
    }
}

/// Everything about "now" that outfit choice depends on.
public struct OutfitContext {
    public var occasion: Occasion
    public var weather: Weather
    public var date: Date
    public var profile: StyleProfile?

    public init(occasion: Occasion, weather: Weather = .mild, date: Date = Date(), profile: StyleProfile? = nil) {
        self.occasion = occasion
        self.weather = weather
        self.date = date
        self.profile = profile
    }
}
