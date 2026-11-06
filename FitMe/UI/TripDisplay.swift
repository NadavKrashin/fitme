import FitEngine
import Foundation

extension Laundry {
    var title: String {
        switch self {
        case .none: "No laundry"
        case .everyThreeDays: "Every 3 days"
        case .everyFiveDays: "Every 5 days"
        case .weekly: "Weekly"
        }
    }
}

extension Luggage {
    var title: String {
        switch self {
        case .carryOn: "Carry-on"
        case .checked: "Checked bag"
        }
    }
}

extension DailyWeather {
    /// "12–19° · 40% rain".
    var summary: String {
        let range = "\(Int(feelsLikeMinC.rounded()))–\(Int(feelsLikeMaxC.rounded()))°"
        let rain = Int((precipitationChance * 100).rounded())
        return rain > 0 ? "\(range) · \(rain)% rain" : range
    }

    var symbolName: String {
        if dressFor.isRainy {
            return "cloud.rain"
        }
        return dressFor.feelsLikeC < 12 ? "cloud.sun" : "sun.max"
    }

    var sourceNote: String {
        switch source {
        case .forecast: "Forecast"
        case .typical: "Typical for these dates"
        case .manual: "No forecast yet"
        }
    }
}

extension TripDetails {
    /// "12–18 Nov" or "28 Nov – 3 Dec".
    var dateRange: String {
        (startDate ..< max(endDate, startDate)).formatted(.interval.day().month(.abbreviated))
    }

    var dayCountText: String {
        days.count == 1 ? "1 day" : "\(days.count) days"
    }
}

extension Date {
    /// "Mon 12 Nov".
    var tripDay: String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
