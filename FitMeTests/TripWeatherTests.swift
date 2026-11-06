import Foundation
import Testing
@testable import FitMe

struct TripWeatherTests {
    private static let geocoding = """
    {"results":[
      {"id":1,"name":"Lisbon","latitude":38.71667,"longitude":-9.13333,"country":"Portugal","admin1":"Lisbon"},
      {"id":2,"name":"Lisbon","latitude":44.03,"longitude":-70.10,"country":"United States","admin1":"Maine"}
    ]}
    """

    /// Days 7 and 8 from `TripFixtures.now`.
    private static let forecast = """
    {"daily":{"time":["2026-11-13","2026-11-14"],
     "apparent_temperature_min":[11.0,12.5],"apparent_temperature_max":[19.0,null],
     "precipitation_probability_max":[20,null]}}
    """

    /// The same two dates in a past year; the archive answers every year with this body.
    private static func archive(_ year: Int) -> String {
        """
        {"daily":{"time":["\(year)-12-20","\(year)-12-21"],
         "apparent_temperature_min":[4.0,6.0],"apparent_temperature_max":[10.0,12.0],
         "precipitation_sum":[3.2,0.0]}}
        """
    }

    private func service(_ bodies: [String: String]) -> (OpenMeteoTripWeather, RoutingTransport) {
        let transport = RoutingTransport(bodies)
        var service = OpenMeteoTripWeather(transport: transport)
        service.calendar = TripFixtures.calendar
        service.now = { TripFixtures.now }
        return (service, transport)
    }

    @Test func searchesCitiesWithTheirRegion() async throws {
        let (service, transport) = service(["geocoding-api.open-meteo.com": Self.geocoding])

        let places = try await service.places(matching: " Lisbon ")

        #expect(places.map(\.detail) == ["Portugal", "Maine, United States"])
        #expect(places.first?.latitude == 38.71667)
        #expect(await transport.requests.first?.url?.query?.contains("name=Lisbon") == true)
    }

    @Test func shortQueriesDontSearch() async throws {
        let (service, transport) = service([:])
        #expect(try await service.places(matching: "L").isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    @Test func daysWithinSixteenDaysUseTheForecast() async throws {
        let (service, transport) = service(["api.open-meteo.com": Self.forecast])

        let days = try await service.dailyWeather(at: TripFixtures.lisbon, days: [TripFixtures.day(7)])

        #expect(days == [DailyWeather(
            feelsLikeMinC: 11,
            feelsLikeMaxC: 19,
            precipitationChance: 0.2,
            source: .forecast
        )])
        let query = try #require(await transport.requests.first?.url?.query)
        #expect(query.contains("start_date=2026-11-13"))
        #expect(query.contains("end_date=2026-11-13"))
        #expect(query.contains("latitude=38.72"))
    }

    @Test func aDayWithMissingValuesFailsRatherThanGuessing() async {
        let (service, _) = service(["api.open-meteo.com": Self.forecast])
        await #expect(throws: WeatherError.unavailable) {
            try await service.dailyWeather(at: TripFixtures.lisbon, days: [TripFixtures.day(8)])
        }
    }

    @Test func laterDaysAverageTheSameDatesInPastYears() async throws {
        let (service, transport) = service([
            "archive-api.open-meteo.com": Self.archive(2025),
        ])
        // The archive fake always answers with 2025 dates; only the 2025 request lines up.
        let days = try await service.dailyWeather(
            at: TripFixtures.lisbon,
            days: [TripFixtures.day(44), TripFixtures.day(45)]
        )

        #expect(await transport.requests.count == OpenMeteoTripWeather.typicalYears)
        #expect(days.map(\.source) == [.typical, .typical])
        #expect(days[0].feelsLikeMinC == 4)
        #expect(days[0].precipitationChance == 1, "it rained 3.2 mm that day")
        #expect(days[1].precipitationChance == 0)
    }

    @Test func serverErrorsBecomeUnavailable() async {
        let (service, _) = service([:])
        await #expect(throws: WeatherError.unavailable) {
            try await service.dailyWeather(at: TripFixtures.lisbon, days: [TripFixtures.day(1)])
        }
    }

    @Test func dressesForTheMiddleOfTheDay() {
        let day = DailyWeather(feelsLikeMinC: 10, feelsLikeMaxC: 20, precipitationChance: 0.6, source: .forecast)
        #expect(day.dressFor.feelsLikeC == 15)
        #expect(day.dressFor.isRainy)
    }
}
