import FitEngine
import Foundation
import Testing
@testable import FitMe

struct OccasionHintTests {
    @Test(arguments: [
        ("Sam & Alex's wedding", Occasion.formal),
        ("Client dinner", .work),
        ("Dinner with Dana", .date),
        ("Morning run", .sport),
        ("Brunch at Benedict", .smartCasual),
        ("Flight to Lisbon", .travel),
        ("Pool day", .beach),
        ("Café meeting", .work),
        ("לחתונה של נועה", .formal),
        ("ארוחת ערב עם דנה", .date),
    ])
    func readsTheOccasionFromATitle(title: String, expected: Occasion) {
        #expect(OccasionHint.occasion(for: title) == expected)
    }

    /// English keywords match whole words only: "brunch" isn't a run, and "Datadog sync" isn't a date.
    @Test(arguments: ["Brunch", "Datadog sync", "Dentist", ""])
    func ignoresPartialWords(title: String) {
        #expect(OccasionHint.occasion(for: title) != .sport)
        #expect(OccasionHint.occasion(for: title) != .date)
    }

    @Test func hintsAreTheMatchingEventsEarliestFirst() {
        let start = TripFixtures.now
        let events = [
            CalendarEvent(title: "Dinner with Dana", start: start.addingTimeInterval(7200), isAllDay: false),
            CalendarEvent(title: "Dentist", start: start, isAllDay: false),
            CalendarEvent(title: "Gym", start: start.addingTimeInterval(3600), isAllDay: false),
        ]

        let hints = OccasionHint.hints(from: events)

        #expect(hints.map(\.title) == ["Gym", "Dinner with Dana"])
        #expect(hints.map(\.occasion) == [.sport, .date])
    }
}

@MainActor
struct TodayCalendarTests {
    let dinner = CalendarEvent(title: "Dinner with Dana", start: TripFixtures.now, isAllDay: false)

    @Test func readsTheRestOfTodayWhenAllowed() async throws {
        let calendar = FakeCalendar(events: [dinner])
        let model = makeTodayModel(calendar: calendar)

        await model.loadCalendarHints(now: TripFixtures.now, calendar: TripFixtures.calendar)

        #expect(model.calendarHints == .hints(OccasionHint.hints(from: [dinner])))
        let range = try #require(calendar.requestedRange)
        #expect(range.lowerBound == TripFixtures.now)
        #expect(range.upperBound == TripFixtures.calendar.startOfDay(for: TripFixtures.now).addingTimeInterval(86400))
    }

    @Test func asksBeforeReadingAndHidesWhenRefused() async {
        let calendar = FakeCalendar(access: .notAsked, grantsOnRequest: false, events: [dinner])
        let model = makeTodayModel(calendar: calendar)

        await model.loadCalendarHints()
        #expect(model.calendarHints == .notAsked)
        #expect(calendar.requestedRange == nil, "events are never read before access is granted")

        await model.connectCalendar()
        #expect(model.calendarHints == .unavailable)
    }

    @Test func dressingForAnEventSwitchesTheOccasion() async {
        let model = makeTodayModel(calendar: FakeCalendar(events: [dinner]))
        await model.loadCalendarHints()
        guard case let .hints(hints) = model.calendarHints, let hint = hints.first else {
            Issue.record("expected a hint")
            return
        }

        model.dress(for: hint)

        #expect(model.occasion == .date)
        #expect(model.toast?.message == "Dressing for Dinner with Dana")
    }

    /// Three meetings all call for work; dressing for one must not mark the other two.
    @Test func onlyTheTappedEventIsMarked() async {
        let meetings = (0 ..< 3).map {
            CalendarEvent(
                title: "Meeting \($0)",
                start: TripFixtures.now.addingTimeInterval(Double($0) * 3600),
                isAllDay: false
            )
        }
        let model = makeTodayModel(calendar: FakeCalendar(events: meetings))
        await model.loadCalendarHints()
        guard case let .hints(hints) = model.calendarHints, hints.count == 3 else {
            Issue.record("expected three hints")
            return
        }

        model.dress(for: hints[1])

        #expect(hints.map(model.isDressing(for:)) == [false, true, false])
        model.occasion = .casual
        #expect(!model.isDressing(for: hints[1]), "picking another occasion by hand clears it")
    }
}
