import FitEngine
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var model: TodayModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    OutfitPlanner(model: model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Today")
        }
        .task {
            if model == nil {
                model = dependencies.makeTodayModel(anchor: nil)
            }
        }
    }
}

/// Outfits built around one closet item, opened from its detail screen.
struct OutfitsWithItemView: View {
    @Environment(\.dependencies) private var dependencies
    let item: Item
    @State private var model: TodayModel?

    var body: some View {
        Group {
            if let model {
                OutfitPlanner(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("With \(item.name)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = dependencies.makeTodayModel(anchor: item)
            }
        }
    }
}

/// Plans (occasion, weather), suggestions with reactions, and the optional stylist. Shared by Today and
/// "Outfits with this item".
private struct OutfitPlanner: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var model: TodayModel
    @Query(sort: \ItemRecord.addedAt) private var records: [ItemRecord]
    @Query private var profiles: [StyleProfileRecord]

    private var closet: [Item] {
        records.map(\.item)
    }

    private var profile: StyleProfile {
        profiles.first?.profile ?? StyleProfile()
    }

    var body: some View {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.itemID, $0) })
        let image: (String) -> Data? = { recordsByID[$0]?.cutout }

        List {
            Section("Plans") {
                WeatherRow(state: model.weather) { Task { await model.loadWeather() } }
                Picker("Occasion", selection: $model.occasion) {
                    ForEach(Occasion.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Feels like \(model.feelsLikeC, format: .number.precision(.fractionLength(0)))°C")
                    Slider(value: $model.feelsLikeC, in: TodayModel.temperatureRange, step: 1)
                        .accessibilityLabel("Feels-like temperature")
                }
                Toggle("Rain expected", isOn: $model.isRainy)
            }

            Section("Suggestions") {
                if closet.isEmpty {
                    Text("Your closet is empty.").foregroundStyle(.secondary)
                } else if model.suggestions.isEmpty {
                    Text("Nothing in your closet fits this occasion and weather.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.suggestions) { suggestion in
                        card(for: suggestion, image: image)
                    }
                }
            }

            if !closet.isEmpty {
                stylistSection(image: image)
            }
        }
        .task {
            if model.weather == .idle {
                await model.loadWeather()
            }
        }
        .task(id: RefreshKey(model: model, closet: closet)) {
            await model.refresh(closet: closet, profile: profile)
        }
    }

    private func stylistSection(image: @escaping (String) -> Data?) -> some View {
        Section {
            switch model.stylist {
            case .idle:
                Button("Ask the stylist") { Task { await model.askStylist(closet: closet, profile: profile) } }
            case .loading:
                HStack {
                    ProgressView()
                    Text("The stylist is looking through your closet…")
                }
            case let .picked(picks):
                ForEach(picks, id: \.outfit.id) { pick in
                    card(for: pick.outfit, image: image, reason: pick.reason)
                }
            case let .failed(message):
                Text(message).foregroundStyle(.red)
                Button("Try again") { Task { await model.askStylist(closet: closet, profile: profile) } }
            }
        } header: {
            Text("Stylist")
        } footer: {
            Text("Claude reviews a dozen candidates for color, proportion and occasion, and explains its picks.")
        }
    }

    private func card(
        for outfit: ScoredOutfit,
        image: @escaping (String) -> Data?,
        reason: String? = nil
    ) -> some View {
        OutfitCard(outfit: outfit, image: image, reason: reason, reaction: model.feedback[outfit.id]) { reaction in
            model.react(reaction, to: outfit, recorder: FeedbackRecorder(context: modelContext))
        }
    }

    /// Re-run suggestions whenever an input or the closet changes (not on reactions, so the list doesn't jump).
    private struct RefreshKey: Equatable {
        let occasion: Occasion
        let feelsLikeC: Double
        let isRainy: Bool
        let itemIDs: [String]

        @MainActor
        init(model: TodayModel, closet: [Item]) {
            occasion = model.occasion
            feelsLikeC = model.feelsLikeC
            isRainy = model.isRainy
            itemIDs = closet.map(\.id)
        }
    }
}

private struct WeatherRow: View {
    let state: TodayModel.WeatherState
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            Label("Getting today's weather…", systemImage: "cloud.sun")
                .foregroundStyle(.secondary)
        case let .loaded(forecast):
            Label {
                Text(summary(forecast))
            } icon: {
                Image(systemName: forecast.precipitationChance >= 0.5 ? "cloud.rain" : "sun.max")
            }
        case let .failed(message):
            HStack {
                Label(message, systemImage: "location.slash").foregroundStyle(.secondary)
                Spacer()
                Button("Retry", action: onRetry).buttonStyle(.borderless)
            }
        }
    }

    private func summary(_ forecast: DayForecast) -> String {
        let range = "\(Int(forecast.feelsLikeMinC.rounded()))–\(Int(forecast.feelsLikeMaxC.rounded()))°C"
        let rain = Int((forecast.precipitationChance * 100).rounded())
        return "Feels like \(Int(forecast.feelsLikeNowC.rounded()))°C now · \(range) today · \(rain)% rain"
    }
}

#if DEBUG
#Preview {
    TodayView()
        .environment(\.dependencies, .preview())
        .environment(PreviewData.captureModel)
        .modelContainer(PreviewData.container)
}
#endif
