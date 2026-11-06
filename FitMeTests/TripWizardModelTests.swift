import FitEngine
import Foundation
import SwiftData
import Testing
@testable import FitMe

@MainActor
struct TripWizardModelTests {
    let closet = try! DemoCloset.items()
    let container = try! Persistence.makeInMemoryContainer()

    private func wizard(weather: FakeTripWeather = .init(), editing: TripRecord? = nil) -> TripWizardModel {
        let model = TripWizardModel(existing: editing, weatherService: weather, planner: TripPlanner())
        model.details.startDate = TripFixtures.day(1)
        return model
    }

    @Test func needsAStopToContinue() {
        let model = wizard()
        #expect(!model.canContinue)
        model.addStop(TripFixtures.lisbon)
        #expect(model.canContinue)
        #expect(model.details.stops.first?.nights == TripWizardModel.defaultNights)
    }

    @Test func layingOutFillsWeatherForEveryDay() async {
        let model = wizard()
        model.addStop(TripFixtures.lisbon)

        await model.layOutDays()

        #expect(model.details.days.count == TripWizardModel.defaultNights + 1)
        #expect(model.details.days.allSatisfy { $0.weather == FakeTripWeather().day })
        #expect(model.weather == .loaded)
    }

    @Test func aStopWithoutWeatherIsNamedAndKeepsMildDefaults() async {
        let model = wizard(weather: FakeTripWeather(failing: ["Porto"]))
        model.addStop(TripFixtures.lisbon)
        model.addStop(TripFixtures.porto)

        await model.layOutDays()

        guard case let .failed(message) = model.weather else {
            Issue.record("expected a failure")
            return
        }
        #expect(message.contains("Porto"))
        #expect(!message.contains("Lisbon"))
        let portoDays = model.details.dayIndices(at: model.details.stops[1])
        #expect(portoDays.allSatisfy { model.details.days[$0].weather == .unknown })
    }

    @Test func everyDayKeepsAtLeastOneOccasion() async {
        let model = wizard()
        model.addStop(TripFixtures.lisbon)
        await model.layOutDays()

        model.toggle(.travel, onDay: 0)
        #expect(model.details.days[0].occasions == [.travel])

        model.toggle(.formal, onDay: 1)
        model.toggle(.date, onDay: 1)
        #expect(model.details.days[1].occasions == [.casual, .date, .formal], "kept in the occasion order")
    }

    @Test func packingSavesANewTrip() async throws {
        let model = wizard()
        model.addStop(TripFixtures.lisbon)
        await model.layOutDays()

        let trip = await model.pack(closet: closet, context: container.mainContext)

        #expect(try container.mainContext.fetch(FetchDescriptor<TripRecord>()).map(\.tripID) == [trip.tripID])
        #expect(trip.name == "Lisbon")
        #expect(!trip.details.packedItemIDs.isEmpty)
        #expect(!model.isPacking)
    }

    @Test func editingRepacksTheSameTrip() async throws {
        let first = wizard()
        first.addStop(TripFixtures.lisbon)
        await first.layOutDays()
        let trip = await first.pack(closet: closet, context: container.mainContext)

        let edit = wizard(editing: trip)
        edit.details.stops[0].nights = 6
        await edit.layOutDays()
        _ = await edit.pack(closet: closet, context: container.mainContext)

        let trips = try container.mainContext.fetch(FetchDescriptor<TripRecord>())
        #expect(trips.count == 1)
        #expect(trips.first?.details.days.count == 7)
    }
}
