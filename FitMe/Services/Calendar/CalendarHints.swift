import EventKit
import FitEngine
import Foundation
import os

struct CalendarEvent: Equatable, Sendable {
    let title: String
    let start: Date
    let isAllDay: Bool
}

enum CalendarAccess: Equatable, Sendable {
    case notAsked
    case granted
    case denied
}

protocol CalendarReading: Sendable {
    var access: CalendarAccess { get }
    /// Shows the system prompt the first time; returns whether FitMe may read events.
    func requestAccess() async -> Bool
    func events(from start: Date, to end: Date) async -> [CalendarEvent]
}

/// Reads the user's calendars with EventKit. An actor because `EKEventStore` isn't `Sendable`.
actor EventKitCalendar: CalendarReading {
    private let store = EKEventStore()

    nonisolated var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    Logger.today.error("Calendar access request failed: \(String(describing: error))")
                }
                continuation.resume(returning: granted)
            }
        }
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map {
            CalendarEvent(title: $0.title ?? "", start: $0.startDate, isAllDay: $0.isAllDay)
        }
    }
}

/// A calendar event worth dressing for.
struct CalendarHint: Identifiable, Equatable, Sendable {
    let title: String
    let start: Date
    let isAllDay: Bool
    let occasion: Occasion

    var id: String {
        "\(start.timeIntervalSince1970)|\(title)"
    }
}

/// Guesses what to dress for from an event's title, on the device: titles are never sent anywhere.
enum OccasionHint {
    /// The most events to suggest at once.
    static let limit = 3

    /// Checked in order, so the most demanding dress code wins: a "client dinner" is work, not a date.
    private static let keywords: [(occasion: Occasion, words: [String])] = [
        (.formal, ["wedding", "gala", "black tie", "ceremony", "opera", "funeral", "awards", "reception", "חתונה"]),
        (.sport, [
            "gym", "workout", "run", "running", "training", "yoga", "pilates", "crossfit", "tennis", "padel",
            "football", "soccer", "basketball", "cycling", "hike", "hiking", "climbing",
            "אימון", "חדר כושר", "ריצה", "יוגה",
        ]),
        (.beach, ["beach", "pool", "swim", "swimming", "בריכה"]),
        (.travel, ["flight", "airport", "טיסה"]),
        (.work, [
            "meeting", "interview", "office", "client", "presentation", "conference", "workshop", "standup",
            "פגישה", "ראיון",
        ]),
        (.date, ["date", "dinner", "drinks", "anniversary", "דייט", "ארוחת ערב"]),
        (.smartCasual, [
            "brunch", "theater", "theatre", "concert", "party", "birthday", "museum",
            "בראנץ", "מסיבה", "יום הולדת",
        ]),
    ]

    static func occasion(for title: String) -> Occasion? {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        // English keywords must be whole words ("run" isn't "brunch"). Hebrew joins prepositions onto the word
        // ("לחתונה", to the wedding), so its keywords match inside words.
        let words = " " + folded.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }
            .joined(separator: " ") + " "
        return keywords.first { _, list in
            list.contains { keyword in
                keyword.unicodeScalars.allSatisfy(\.isASCII)
                    ? words.contains(" \(keyword) ")
                    : folded.contains(keyword)
            }
        }?.occasion
    }

    /// The events today that suggest an occasion, earliest first.
    static func hints(from events: [CalendarEvent]) -> [CalendarHint] {
        let hints = events.compactMap { event in
            occasion(for: event.title).map {
                CalendarHint(title: event.title, start: event.start, isAllDay: event.isAllDay, occasion: $0)
            }
        }
        return Array(hints.sorted { ($0.start, $0.title) < ($1.start, $1.title) }.prefix(limit))
    }
}
