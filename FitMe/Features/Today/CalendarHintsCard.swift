import FitEngine
import SwiftUI

/// Today's events worth dressing for, or the prompt to allow reading the calendar.
struct CalendarHintsCard: View {
    let model: TodayModel
    @AppStorage("calendarPromptDismissed") private var isCalendarPromptDismissed = false

    var body: some View {
        switch model.calendarHints {
        case .notAsked where !isCalendarPromptDismissed:
            VStack(alignment: .leading, spacing: 12) {
                Label("Plans today?", systemImage: "calendar")
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.ink)
                Text("FitMe can look at today's calendar and pick the occasion for you. Event titles stay on your "
                    + "phone.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
                HStack(spacing: 10) {
                    Button("Use my calendar") { Task { await model.connectCalendar() } }
                        .buttonStyle(.pill(.accent))
                    Button("Not now") { isCalendarPromptDismissed = true }
                        .buttonStyle(.pill(.quiet))
                }
            }
            .card()
        case let .hints(hints) where !hints.isEmpty:
            VStack(alignment: .leading, spacing: 12) {
                Label("From your calendar", systemImage: "calendar")
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.ink)
                ForEach(hints) { hint in
                    CalendarHintRow(hint: hint, isChosen: model.isDressing(for: hint)) {
                        model.dress(for: hint)
                    }
                }
            }
            .card()
        default:
            EmptyView()
        }
    }
}

/// One event, what it calls for, and a button to dress for it.
private struct CalendarHintRow: View {
    let hint: CalendarHint
    let isChosen: Bool
    let onDress: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hint.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(hint.isAllDay ? "All day" : hint.start.formatted(date: .omitted, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(Theme.inkMuted)
                    Badge(text: hint.occasion.title, tint: Theme.tint(for: hint.occasion))
                }
            }
            Spacer(minLength: 8)
            if isChosen {
                Label("Dressing for it", systemImage: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.sageInk)
            } else {
                Button("Dress for it", action: onDress)
                    .buttonStyle(.pill(.quiet))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
