import CoreLocation
import Foundation
import Testing
@testable import FitMe

struct WeatherServiceTests {
    private static let sample = """
    {"latitude":32.08,"longitude":34.78,
     "current":{"time":"2026-11-06T09:00","interval":900,"apparent_temperature":14.6},
     "daily":{"time":["2026-11-06"],"apparent_temperature_min":[11.2],"apparent_temperature_max":[22.4],
     "precipitation_probability_max":[35]}}
    """

    @Test func requestsTodayAtRoundedCoordinates() throws {
        let url = OpenMeteoWeatherService.url(for: CLLocationCoordinate2D(latitude: 32.08532, longitude: 34.78177))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(url.host == "api.open-meteo.com")
        #expect(query["latitude"] == "32.09")
        #expect(query["longitude"] == "34.78")
        #expect(query["current"] == "apparent_temperature")
        #expect(query["daily"]?.contains("precipitation_probability_max") == true)
        #expect(query["forecast_days"] == "1")
    }

    @Test func parsesTheForecast() throws {
        let forecast = try OpenMeteoWeatherService.parse(Data(Self.sample.utf8))
        #expect(forecast == DayForecast(
            feelsLikeNowC: 14.6,
            feelsLikeMinC: 11.2,
            feelsLikeMaxC: 22.4,
            precipitationChance: 0.35
        ))
    }

    @Test func missingRainProbabilityMeansNoRain() throws {
        let json = Self.sample.replacingOccurrences(of: "[35]", with: "[null]")
        #expect(try OpenMeteoWeatherService.parse(Data(json.utf8)).precipitationChance == 0)
    }

    @Test func forecastsWhereTheUserIs() async throws {
        let transport = RecordingTransport(body: Self.sample)
        let service = OpenMeteoWeatherService(locator: FakeLocator(), transport: transport)

        let forecast = try await service.forecastHere()

        #expect(forecast.feelsLikeNowC == 14.6)
        #expect(await transport.requests.first?.url?.query?.contains("latitude=32.09") == true)
    }

    @Test func serverErrorsBecomeUnavailable() async {
        let service = OpenMeteoWeatherService(
            locator: FakeLocator(),
            transport: RecordingTransport(status: 500, body: "{}")
        )
        await #expect(throws: WeatherError.unavailable) { try await service.forecastHere() }
    }
}
