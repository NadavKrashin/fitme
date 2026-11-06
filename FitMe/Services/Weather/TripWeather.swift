import FitEngine
import Foundation

/// A city on a trip.
struct Place: Codable, Hashable, Sendable {
    let name: String
    /// Region and country, to tell Paris, France from Paris, Texas.
    let detail: String
    let latitude: Double
    let longitude: Double
}

/// One day's weather at a trip stop.
struct DailyWeather: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        /// Open-Meteo's forecast, up to 16 days ahead.
        case forecast
        /// The average of the same dates in recent years, for days beyond the forecast.
        case typical
        /// Set by hand, e.g. when the weather couldn't be fetched.
        case manual
    }

    var feelsLikeMinC: Double
    var feelsLikeMaxC: Double
    /// 0...1. For typical weather, the share of recent years in which it rained that day.
    var precipitationChance: Double
    var source: Source

    /// What to dress for: the middle of the day's range. Layers cover the cool morning.
    var dressFor: Weather {
        Weather(feelsLikeC: (feelsLikeMinC + feelsLikeMaxC) / 2, precipitationChance: precipitationChance)
    }

    /// Used until real weather arrives, or when it can't.
    static let unknown = DailyWeather(feelsLikeMinC: 16, feelsLikeMaxC: 24, precipitationChance: 0, source: .manual)
}

protocol PlaceSearching: Sendable {
    func places(matching query: String) async throws -> [Place]
}

protocol TripWeatherProviding: Sendable {
    /// Weather for each of `days` (start-of-day dates) at `place`, in the same order.
    func dailyWeather(at place: Place, days: [Date]) async throws -> [DailyWeather]
}

/// City search and per-day trip weather from Open-Meteo (free, no API key): the forecast where it reaches, and
/// typical weather from the same dates in past years beyond it.
struct OpenMeteoTripWeather: PlaceSearching, TripWeatherProviding {
    /// Open-Meteo forecasts today plus 15 days.
    static let forecastHorizonDays = 15
    static let typicalYears = 3
    /// A day with at least this much rain counts as rainy when averaging past years.
    static let rainyDayMillimeters = 1.0

    let transport: any HTTPTransport
    var calendar = Calendar.current
    var now: @Sendable () -> Date = { .now }

    func places(matching query: String) async throws -> [Place] {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2 else { return [] }
        let data = try await fetch(Self.url(host: "geocoding-api.open-meteo.com", path: "/v1/search", query: [
            "name": name,
            "count": "8",
            "language": "en",
            "format": "json",
        ]))
        return try Self.parsePlaces(data)
    }

    func dailyWeather(at place: Place, days: [Date]) async throws -> [DailyWeather] {
        let today = calendar.startOfDay(for: now())
        guard let horizon = calendar.date(byAdding: .day, value: Self.forecastHorizonDays, to: today) else {
            throw WeatherError.unavailable
        }
        let forecastDays = days.filter { $0 >= today && $0 <= horizon }
        let typicalDays = days.filter { !forecastDays.contains($0) }

        var byDay: [String: DailyWeather] = [:]
        if let first = forecastDays.first, let last = forecastDays.last {
            try await byDay.merge(forecast(at: place, from: first, through: last)) { $1 }
        }
        if let first = typicalDays.first, let last = typicalDays.last {
            let typical = try await typicalWeather(at: place, from: first, through: last)
            for day in typicalDays {
                byDay[stamp(day)] = typical[stamp(day)]
            }
        }
        return try days.map { day in
            guard let weather = byDay[stamp(day)] else { throw WeatherError.unavailable }
            return weather
        }
    }

    // MARK: Requests

    private func forecast(
        at place: Place,
        from first: Date,
        through last: Date
    ) async throws -> [String: DailyWeather] {
        let data = try await fetch(Self.url(host: "api.open-meteo.com", path: "/v1/forecast", query: [
            "latitude": Self.rounded(place.latitude),
            "longitude": Self.rounded(place.longitude),
            "daily": "apparent_temperature_min,apparent_temperature_max,precipitation_probability_max",
            "timezone": "auto",
            "start_date": stamp(first),
            "end_date": stamp(last),
        ]))
        let daily = try Self.parseDaily(data)
        var result: [String: DailyWeather] = [:]
        for (index, stamp) in daily.time.enumerated() {
            guard let day = daily.day(at: index) else { continue }
            result[stamp] = DailyWeather(
                feelsLikeMinC: day.feelsLikeMinC,
                feelsLikeMaxC: day.feelsLikeMaxC,
                precipitationChance: (day.precipitationPercent ?? 0) / 100,
                source: .forecast
            )
        }
        return result
    }

    /// Averages the same dates over the last few years, keyed by this trip's day stamps.
    private func typicalWeather(at place: Place, from first: Date, through last: Date) async throws
        -> [String: DailyWeather] {
        var samples: [String: [DailySeries.Day]] = [:]
        for yearsBack in 1 ... Self.typicalYears {
            guard let pastFirst = calendar.date(byAdding: .year, value: -yearsBack, to: first),
                  let pastLast = calendar.date(byAdding: .year, value: -yearsBack, to: last)
            else { continue }
            let data = try await fetch(Self.url(host: "archive-api.open-meteo.com", path: "/v1/archive", query: [
                "latitude": Self.rounded(place.latitude),
                "longitude": Self.rounded(place.longitude),
                "daily": "apparent_temperature_min,apparent_temperature_max,precipitation_sum",
                "timezone": "auto",
                "start_date": stamp(pastFirst),
                "end_date": stamp(pastLast),
            ]))
            let daily = try Self.parseDaily(data)
            let past = Dictionary(daily.time.enumerated().map { ($1, $0) }) { first, _ in first }
            var day = first
            while day <= last {
                if let pastDay = calendar.date(byAdding: .year, value: -yearsBack, to: day),
                   let index = past[stamp(pastDay)],
                   let sample = daily.day(at: index) {
                    samples[stamp(day), default: []].append(sample)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return samples.mapValues { years in
            let count = Double(years.count)
            let rainyYears = years.count { ($0.precipitationMillimeters ?? 0) >= Self.rainyDayMillimeters }
            return DailyWeather(
                feelsLikeMinC: years.map(\.feelsLikeMinC).reduce(0, +) / count,
                feelsLikeMaxC: years.map(\.feelsLikeMaxC).reduce(0, +) / count,
                precipitationChance: Double(rainyYears) / count,
                source: .typical
            )
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await transport.send(URLRequest(url: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherError.unavailable }
        return data
    }

    /// "2026-11-06" in the user's calendar: trip days are calendar dates, not instants.
    func stamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Parsing

    static func url(host: String, path: String, query: [String: String]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // Built from constant parts and percent-encoded values; cannot fail.
        return components.url! // swiftlint:disable:this force_unwrapping
    }

    /// Two decimals is about 1 km: plenty for a city's weather.
    static func rounded(_ degrees: Double) -> String {
        String(format: "%.2f", degrees)
    }

    static func parsePlaces(_ data: Data) throws -> [Place] {
        guard let response = try? JSONDecoder().decode(GeocodingResponse.self, from: data) else {
            throw WeatherError.unavailable
        }
        return (response.results ?? []).map { result in
            Place(
                name: result.name,
                detail: [result.admin1, result.country].compactMap(\.self).filter { $0 != result.name }
                    .joined(separator: ", "),
                latitude: result.latitude,
                longitude: result.longitude
            )
        }
    }

    static func parseDaily(_ data: Data) throws -> DailySeries {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(DailyResponse.self, from: data) else {
            throw WeatherError.unavailable
        }
        return response.daily
    }
}

/// Open-Meteo's daily arrays, aligned by index with `time`. Any value can be null where a model has no data.
struct DailySeries: Decodable {
    let time: [String]
    let apparentTemperatureMin: [Double?]
    let apparentTemperatureMax: [Double?]
    let precipitationProbabilityMax: [Double?]?
    let precipitationSum: [Double?]?

    struct Day {
        let feelsLikeMinC: Double
        let feelsLikeMaxC: Double
        let precipitationPercent: Double?
        let precipitationMillimeters: Double?
    }

    /// The values for `time[index]`, or nil when either temperature is missing.
    func day(at index: Int) -> Day? {
        guard let min = apparentTemperatureMin[safe: index].flatMap(\.self),
              let max = apparentTemperatureMax[safe: index].flatMap(\.self)
        else { return nil }
        return Day(
            feelsLikeMinC: min,
            feelsLikeMaxC: max,
            precipitationPercent: precipitationProbabilityMax?[safe: index].flatMap(\.self),
            precipitationMillimeters: precipitationSum?[safe: index].flatMap(\.self)
        )
    }
}

private struct DailyResponse: Decodable {
    let daily: DailySeries
}

private struct GeocodingResponse: Decodable {
    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
    }

    /// Missing when nothing matches.
    let results: [Result]?
}
