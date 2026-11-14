import CoreLocation
import Foundation

struct DayForecast: Equatable, Sendable {
    let feelsLikeNowC: Double
    /// The rest of today, from now until 11 pm (the whole day when hourly data is missing).
    let feelsLikeMinC: Double
    let feelsLikeMaxC: Double
    /// Highest chance of rain today, 0...1.
    let precipitationChance: Double
}

enum WeatherError: Error, Equatable {
    case locationDenied
    case locationUnavailable
    case unavailable

    var userMessage: String {
        switch self {
        case .locationDenied: "Location is off for FitMe, so set the temperature yourself."
        case .locationUnavailable: "Couldn't find your location. Set the temperature yourself."
        case .unavailable: "Couldn't get the weather. Set the temperature yourself."
        }
    }
}

protocol WeatherProviding: Sendable {
    /// Today's forecast where the user is.
    func forecastHere() async throws -> DayForecast
}

protocol Locating: Sendable {
    func currentCoordinate() async throws -> CLLocationCoordinate2D
}

/// Forecasts from Open-Meteo (free, no API key). The location is rounded to about 1 km before it leaves the device.
struct OpenMeteoWeatherService: WeatherProviding {
    let locator: any Locating
    let transport: any HTTPTransport

    func forecastHere() async throws -> DayForecast {
        let coordinate = try await locator.currentCoordinate()
        let (data, response) = try await transport.send(URLRequest(url: Self.url(for: coordinate)))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherError.unavailable }
        return try Self.parse(data)
    }

    static func url(for coordinate: CLLocationCoordinate2D) -> URL {
        /// Two decimals is about 1 km: plenty for weather, and less precise than the user's actual position.
        func rounded(_ degrees: Double) -> String {
            String(format: "%.2f", degrees)
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: rounded(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: rounded(coordinate.longitude)),
            URLQueryItem(name: "current", value: "apparent_temperature"),
            URLQueryItem(name: "hourly", value: "apparent_temperature"),
            URLQueryItem(
                name: "daily",
                value: "apparent_temperature_min,apparent_temperature_max,precipitation_probability_max"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        // Built from constant parts above; cannot fail.
        return components.url! // swiftlint:disable:this force_unwrapping
    }

    static func parse(_ data: Data) throws -> DayForecast {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(OpenMeteoResponse.self, from: data),
              let min = response.daily.apparentTemperatureMin.first,
              let max = response.daily.apparentTemperatureMax.first
        else { throw WeatherError.unavailable }
        let rainPercent = response.daily.precipitationProbabilityMax?.compactMap(\.self).first ?? 0
        let rest = restOfDay(response)
        return DayForecast(
            feelsLikeNowC: response.current.apparentTemperature,
            feelsLikeMinC: rest.min() ?? min,
            feelsLikeMaxC: rest.max() ?? max,
            precipitationChance: rainPercent / 100
        )
    }

    /// Feels-like temperatures from now until 11 pm, now included: the hours the user is likely out. The daily low
    /// usually falls in the small hours, which says nothing about what to wear. Times are local ("yyyy-MM-ddTHH:mm").
    private static func restOfDay(_ response: OpenMeteoResponse) -> [Double] {
        guard let hourly = response.hourly else { return [] }
        let thisHour = response.current.time.prefix(13) + ":00"
        let later = zip(hourly.time, hourly.apparentTemperature)
            .filter { time, _ in time >= thisHour && time.suffix(5) <= "23:00" }
            .map(\.1)
        return later.isEmpty ? [] : later + [response.current.apparentTemperature]
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let time: String
        let apparentTemperature: Double
    }

    struct Hourly: Decodable {
        let time: [String]
        let apparentTemperature: [Double]
    }

    struct Daily: Decodable {
        let apparentTemperatureMin: [Double]
        let apparentTemperatureMax: [Double]
        /// Null for some locations' weather models.
        let precipitationProbabilityMax: [Double?]?
    }

    let current: Current
    /// Missing in older responses and test fixtures; the daily range stands in.
    let hourly: Hourly?
    let daily: Daily
}

/// One-shot, city-level location through Core Location, asking for when-in-use permission the first time.
@MainActor
final class CoreLocationLocator: NSObject, Locating, CLLocationManagerDelegate {
    /// Created on first use, on the main actor: Core Location delivers callbacks on the thread that made it.
    private var locationManager: CLLocationManager?
    private var pending: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override nonisolated init() {
        super.init()
    }

    private var manager: CLLocationManager {
        if let locationManager {
            return locationManager
        }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager = manager
        return manager
    }

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw WeatherError.locationDenied
        default:
            break
        }
        pending?.resume(throwing: WeatherError.locationUnavailable) // a newer request replaces an older one
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization() // continues in locationManagerDidChangeAuthorization
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        pending?.resume(with: result)
        pending = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard pending != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: finish(.failure(WeatherError.locationDenied))
            default: break // still undetermined: the permission prompt is showing
            }
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            finish(coordinate.map { .success($0) } ?? .failure(WeatherError.locationUnavailable))
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        Task { @MainActor in finish(.failure(WeatherError.locationUnavailable)) }
    }
}
