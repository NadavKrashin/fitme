#if STAGING
import FitEngine
import Foundation
import os
import SwiftData

/// App Store screenshots (`make screenshots`): the demo closet, a packed sample trip, fixed weather, no calendar, and
/// onboarding done, so every run looks the same. Started by the `-FitMeScreenshots` launch argument, Staging only.
enum ScreenshotStage {
    static let launchArgument = "-FitMeScreenshots"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// The app's services with steady weather, an empty calendar and Claude already allowed.
    static func dependencies(_ live: AppDependencies) -> AppDependencies {
        var stage = live
        stage.weather = SteadyWeather()
        stage.calendar = EmptyCalendar()
        stage.aiConsent = AlwaysAllowed()
        return stage
    }

    /// A fresh demo closet. Synchronous, so onboarding sees clothes and stays out of the way.
    @MainActor
    static func loadCloset(into context: ModelContext) {
        do {
            try DemoCloset.load(into: context)
        } catch {
            Logger.demoData.error("Couldn't load the demo closet for screenshots: \(String(describing: error))")
        }
    }

    /// Four nights in Lisbon starting in twelve days, packed from the demo closet.
    @MainActor
    static func packSampleTrip(into context: ModelContext, now: Date = .now) async {
        for trip in (try? context.fetch(FetchDescriptor<TripRecord>())) ?? [] {
            context.delete(trip)
        }
        let closet = ((try? context.fetch(FetchDescriptor<ItemRecord>())) ?? []).map(\.item)
        let lisbon = Place(name: "Lisbon", detail: "Lisbon, Portugal", latitude: 38.72, longitude: -9.14)
        var details = TripDetails(
            startDate: now.addingTimeInterval(12 * 86400),
            stops: [TripStop(place: lisbon, nights: 4)]
        ).laidOut()
        let plans: [[Occasion]] = [[.travel], [.casual, .date], [.casual, .smartCasual], [.casual], [.travel]]
        for index in details.days.indices {
            details.days[index].occasions = plans[min(index, plans.count - 1)]
            details.days[index].weather = DailyWeather(
                feelsLikeMinC: 15,
                feelsLikeMaxC: 23,
                precipitationChance: index == 2 ? 0.6 : 0.1,
                source: .manual
            )
        }
        let packed = await TripPlanner().pack(details, closet: closet, profile: StyleProfile())
        context.insert(TripRecord(details: packed))
        try? context.save()
    }
}

/// A mild, dry day that warms up by the afternoon.
private struct SteadyWeather: WeatherProviding {
    func forecastHere() async throws -> DayForecast {
        DayForecast(feelsLikeNowC: 18, feelsLikeMinC: 15, feelsLikeMaxC: 22, precipitationChance: 0.1)
    }
}

/// Calendar access granted, with nothing on it: no prompt card, no hints.
private struct EmptyCalendar: CalendarReading {
    var access: CalendarAccess {
        .granted
    }

    func requestAccess() async -> Bool {
        true
    }

    func events(from _: Date, to _: Date) async -> [CalendarEvent] {
        []
    }
}

private struct AlwaysAllowed: AIConsentStoring {
    func read() -> AIConsent {
        .allowed
    }

    func write(_: AIConsent) {}
}
#endif
