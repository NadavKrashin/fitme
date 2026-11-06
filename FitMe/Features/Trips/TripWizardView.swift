import FitEngine
import SwiftData
import SwiftUI

/// Plans a new trip, or edits one: where and when, then what each day holds, then packs.
struct TripWizardView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let editing: TripRecord?
    let onPacked: (TripRecord) -> Void
    @State private var model: TripWizardModel?

    var body: some View {
        NavigationStack {
            if let model {
                // The sheet's own dismiss: inside the pushed days step, dismiss would only pop back a step.
                StopsStep(model: model) { trip in
                    dismiss()
                    onPacked(trip)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                model = dependencies.makeTripWizard(editing: editing)
            }
        }
    }
}

// MARK: Step 1: where and when

private struct StopsStep: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: TripWizardModel
    let onPacked: (TripRecord) -> Void
    @State private var isAddingCity = false
    @State private var showsDays = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                stopsCard
                datesCard
                choiceCard("Laundry on the trip", options: Laundry.allCases, selection: $model.details.laundry) {
                    $0.title
                }
                choiceCard("Luggage", options: Luggage.allCases, selection: $model.details.luggage) { $0.title }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .editorialCanvas()
        .navigationTitle(model.existing == nil ? "New trip" : "Edit trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { showsDays = true } label: {
                Text("Next: plan your days").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
            .disabled(!model.canContinue)
            .opacity(model.canContinue ? 1 : 0.4)
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $isAddingCity) {
            PlaceSearchView { model.addStop($0) }
        }
        .navigationDestination(isPresented: $showsDays) {
            DaysStep(model: model, onPacked: onPacked)
        }
    }

    private var stopsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where are you going?")
                .font(Theme.title(20))
                .foregroundStyle(Theme.ink)
            ForEach($model.details.stops) { $stop in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.place.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        if !stop.place.detail.isEmpty {
                            Text(stop.place.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                    Spacer(minLength: 8)
                    Stepper(value: $stop.nights, in: 1 ... TripWizardModel.maxNightsPerStop) {
                        Text(stop.nights == 1 ? "1 night" : "\(stop.nights) nights")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                            .monospacedDigit()
                    }
                    .fixedSize()
                    Button("Remove \(stop.place.name)", systemImage: "xmark.circle.fill") {
                        if let index = model.details.stops.firstIndex(where: { $0.id == stop.id }) {
                            model.removeStops(at: [index])
                        }
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.inkMuted)
                }
                Divider().overlay(Theme.line)
            }
            Button {
                isAddingCity = true
            } label: {
                Label(model.details.stops.isEmpty ? "Choose a city" : "Add another city", systemImage: "plus")
            }
            .buttonStyle(.pill(model.details.stops.isEmpty ? .accent : .quiet))
        }
        .card()
    }

    private var datesCard: some View {
        let laidOut = model.details.laidOut()
        return VStack(alignment: .leading, spacing: 10) {
            DatePicker("Leaving on", selection: $model.details.startDate, displayedComponents: .date)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .tint(Theme.terracotta)
            if !model.details.stops.isEmpty {
                Text("Home on \(laidOut.endDate.tripDay) · \(laidOut.dayCountText)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .card()
    }

    private func choiceCard<Option: Hashable>(
        _ title: String,
        options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.title(17))
                .foregroundStyle(Theme.ink)
            FlowLayout {
                ForEach(options, id: \.self) { option in
                    ChipButton(title: label(option), isOn: selection.wrappedValue == option) {
                        selection.wrappedValue = option
                    }
                }
            }
        }
        .card()
    }
}

// MARK: Step 2: the days

private struct DaysStep: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var model: TripWizardModel
    let onPacked: (TripRecord) -> Void
    @Query private var records: [ItemRecord]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Tap what each day holds. FitMe plans an outfit for each, and packs for all of them.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
                weatherStatus
                ForEach(model.details.days.indices, id: \.self) { index in
                    DayPlanCard(
                        day: model.details.days[index],
                        number: index + 1,
                        place: model.details.stop(forDay: index)?.place.name ?? ""
                    ) { model.toggle($0, onDay: index) }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .editorialCanvas()
        .navigationTitle("Your days")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { packButton }
        .overlay {
            if model.isPacking {
                PackingProgress()
            }
        }
        .task { await model.layOutDays() }
    }

    @ViewBuilder
    private var weatherStatus: some View {
        switch model.weather {
        case .idle, .loaded:
            EmptyView()
        case .loading:
            HStack(spacing: 10) {
                ProgressView().tint(Theme.terracotta)
                Text("Checking the weather…").font(.subheadline).foregroundStyle(Theme.inkMuted)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(Theme.terracotta)
        }
    }

    private var packButton: some View {
        VStack(spacing: 6) {
            if records.isEmpty {
                Text("Add clothes to your closet first.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkMuted)
            }
            Button {
                Task {
                    let trip = await model.pack(closet: records.map(\.item), context: modelContext)
                    onPacked(trip)
                }
            } label: {
                Label(model.existing == nil ? "Pack my bag" : "Repack my bag", systemImage: "suitcase")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.accent))
            .disabled(records.isEmpty || model.isPacking || model.weather == .loading)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 8)
    }
}

private struct DayPlanCard: View {
    let day: TripDayPlan
    let number: Int
    let place: String
    let onToggle: (Occasion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day \(number)")
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.ink)
                Text("\(day.date.tripDay) · \(place)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 0)
            }
            Label {
                Text("\(day.weather.summary) · \(day.weather.sourceNote)")
            } icon: {
                Image(systemName: day.weather.symbolName).foregroundStyle(Theme.sageInk)
            }
            .font(.footnote)
            .foregroundStyle(Theme.inkMuted)
            FlowLayout {
                ForEach(Occasion.allCases, id: \.self) { occasion in
                    ChipButton(
                        title: occasion.title,
                        isOn: day.occasions.contains(occasion),
                        tint: Theme.tint(for: occasion)
                    ) { onToggle(occasion) }
                }
            }
        }
        .card()
    }
}

private struct PackingProgress: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(Theme.terracotta)
            Text("Choosing the fewest pieces that dress every day…")
                .font(.callout)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(Theme.card, in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: Theme.shadow, radius: 20, y: 8)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas.opacity(0.6))
    }
}

// MARK: City search

struct PlaceSearchView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let onPick: (Place) -> Void
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var message: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            List(results, id: \.self) { place in
                Button {
                    onPick(place)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).foregroundStyle(Theme.ink)
                        Text(place.detail).font(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
                .editorialRow()
            }
            .overlay {
                if let message {
                    ContentUnavailableView(message, systemImage: "magnifyingglass")
                }
            }
            .safeAreaInset(edge: .top) { searchField }
            .editorialCanvas()
            .navigationTitle("Add a city")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { isSearchFocused = true }
            .task(id: query) { await search() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
            TextField("City", text: $query)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.card, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.line))
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 8)
    }

    private func search() async {
        do {
            try await Task.sleep(for: .milliseconds(300)) // wait for typing to pause
            results = try await dependencies.places.places(matching: query)
            message = results.isEmpty && query.count >= 2 ? "No cities match \"\(query)\"" : nil
        } catch is CancellationError {
            // A newer query replaced this one.
        } catch {
            message = "Couldn't search. Check your connection."
        }
    }
}

#if DEBUG
#Preview {
    TripWizardView(editing: nil) { _ in }
        .environment(\.dependencies, .preview())
        .modelContainer(PreviewData.container)
}
#endif
