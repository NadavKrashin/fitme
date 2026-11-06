import FitEngine
import Foundation
import Testing
@testable import FitMe

struct TripDetailsTests {
    private let calendar = TripFixtures.calendar

    @Test func oneDayPerNightPlusTheDayHome() {
        let details = TripFixtures.trip(nights: 4)
        #expect(details.days.count == 5)
        #expect(details.days.first?.date == TripFixtures.day(1))
        #expect(details.endDate == TripFixtures.day(5))
    }

    @Test func travelDaysAreTheFirstTheLastAndEachMove() {
        let details = TripFixtures.trip(nights: 2, stops: [TripFixtures.lisbon, TripFixtures.porto])
        #expect(details.days.map(\.occasions) == [[.travel], [.casual], [.travel], [.casual], [.travel]])
        #expect(details.days.indices.map { details.stop(forDay: $0)?.place.name } == [
            "Lisbon", "Lisbon", "Porto", "Porto", "Porto",
        ])
    }

    @Test func relayingOutKeepsPlansButNotAnotherCitysWeather() {
        var details = TripFixtures.trip(nights: 2, stops: [TripFixtures.lisbon, TripFixtures.porto])
        details.days[1].occasions = [.formal]
        details.stops.remove(at: 1)

        let relaidOut = details.laidOut(calendar: calendar)

        #expect(relaidOut.days.count == 3)
        #expect(relaidOut.days[1].occasions == [.formal])
        #expect(relaidOut.days[1].weather == FakeTripWeather().day, "same stop, same date: weather kept")

        details.startDate = TripFixtures.day(10)
        #expect(details.laidOut(calendar: calendar).days.allSatisfy { $0.weather == .unknown }, "new dates")
    }

    @Test func phaseFollowsTheDates() {
        let details = TripFixtures.trip(nights: 2)
        #expect(details.phase(now: TripFixtures.now, calendar: calendar) == .upcoming)
        #expect(details.phase(now: TripFixtures.day(2), calendar: calendar) == .ongoing)
        #expect(details.phase(now: TripFixtures.day(4), calendar: calendar) == .finished)
        #expect(details.dayIndex(of: TripFixtures.day(2), calendar: calendar) == 1)
    }

    @Test func namesFromStops() {
        #expect(TripFixtures.trip(stops: [TripFixtures.lisbon]).name == "Lisbon")
        #expect(TripFixtures.trip(stops: [TripFixtures.lisbon, TripFixtures.porto]).name == "Lisbon & Porto")
        let three = [TripFixtures.lisbon, TripFixtures.porto, TripFixtures.lisbon]
        #expect(TripFixtures.trip(stops: three).name == "Lisbon, Porto +1")
    }

    @Test func survivesAStoreRoundTrip() {
        var details = TripFixtures.trip()
        details.packedItemIDs = ["t01"]
        details.checkedOff = ["t01", "Socks"]
        let record = TripRecord(details: details)
        #expect(record.details == details)
        #expect(record.endDate == details.endDate)
    }
}

struct TripStorageCompatibilityTests {
    /// Trips saved before `repeatsAPiece` existed must still load.
    @Test func plannedOutfitsFromBeforeRepeatFlagsDecode() throws {
        let json = #"{"dayIndex":2,"occasion":"casual","itemIDs":["t01","b01"]}"#
        let planned = try JSONDecoder().decode(PlannedOutfit.self, from: Data(json.utf8))
        #expect(planned == PlannedOutfit(dayIndex: 2, occasion: .casual, itemIDs: ["t01", "b01"]))
    }
}
