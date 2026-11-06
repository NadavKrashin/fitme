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
            .editorialCanvas()
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
        .navigationTitle("With \(item.name.lowercased())")
        .navigationBarTitleDisplayMode(.inline)
        .editorialCanvas()
        .task {
            if model == nil {
                model = dependencies.makeTodayModel(anchor: item)
            }
        }
    }
}

/// Plans (weather, occasion), suggestions with reactions, and the optional stylist. Shared by Today and
/// "Outfits with this item".
private struct OutfitPlanner: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var model: TodayModel
    @Query(sort: \ItemRecord.addedAt) private var records: [ItemRecord]
    @Query private var profiles: [StyleProfileRecord]
    @Query private var savedOutfits: [SavedOutfit]

    private var closet: [Item] {
        records.map(\.item)
    }

    private var profile: StyleProfile {
        profiles.first?.profile ?? StyleProfile()
    }

    var body: some View {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.itemID, $0) })
        let image: (String) -> Data? = { recordsByID[$0]?.cutout }
        let savedIDs = Set(savedOutfits.map(\.outfitID))

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)

                WeatherCard(state: model.weather) { Task { await model.loadWeather() } }
                occasionChips
                conditionsCard

                SectionTitle(text: "Suggestions")
                if closet.isEmpty {
                    emptyCard("Your closet is empty. Add photos of your clothes from the Closet tab.")
                } else if model.suggestions.isEmpty {
                    emptyCard("Nothing in your closet suits this occasion and weather yet.")
                } else {
                    ForEach(model.suggestions) { suggestion in
                        card(for: suggestion, image: image, isSaved: savedIDs.contains(suggestion.id))
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .scale(scale: 0.9).combined(with: .opacity)
                            ))
                    }
                }

                if !closet.isEmpty {
                    stylistSection(image: image, savedIDs: savedIDs)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 80)
            .animation(.spring(duration: 0.4), value: model.suggestions)
        }
        .toast(model.toast) { model.toast = nil }
        .task {
            if model.weather == .idle {
                await model.loadWeather()
            }
        }
        .task(id: RefreshKey(model: model, closet: closet)) {
            await model.refresh(closet: closet, profile: profile)
        }
    }

    // MARK: Plans

    private var occasionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Occasion.allCases, id: \.self) { occasion in
                    ChipButton(
                        title: occasion.title,
                        isOn: model.occasion == occasion,
                        tint: Theme.tint(for: occasion)
                    ) {
                        model.occasion = occasion
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .padding(.horizontal, -Theme.gutter)
    }

    private var conditionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Feels like")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                Text("\(Int(model.feelsLikeC))°")
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Spacer()
                Toggle(isOn: $model.isRainy) {
                    Label("Rain", systemImage: "cloud.rain")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                }
                .fixedSize()
                .tint(Theme.terracotta)
            }
            Slider(value: $model.feelsLikeC, in: TodayModel.temperatureRange, step: 1)
                .tint(Theme.terracotta)
                .accessibilityLabel("Feels-like temperature")
        }
        .card()
    }

    // MARK: Suggestions

    private func card(
        for outfit: ScoredOutfit,
        image: @escaping (String) -> Data?,
        isSaved: Bool,
        reason: String? = nil
    ) -> some View {
        let recorder = FeedbackRecorder(context: modelContext)
        return OutfitCard(
            outfit: outfit,
            image: image,
            reason: reason,
            isSaved: isSaved,
            isWorn: model.worn.contains(outfit.id),
            onToggleSave: { model.toggleSaved(outfit, isSaved: isSaved, recorder: recorder) },
            onDismiss: reason == nil ? { model.dismiss(outfit, recorder: recorder) } : nil,
            onWear: { model.wear(outfit, recorder: recorder) }
        )
    }

    private func emptyCard(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(Theme.inkMuted)
            .card()
    }

    // MARK: Stylist

    @ViewBuilder
    private func stylistSection(image: @escaping (String) -> Data?, savedIDs: Set<String>) -> some View {
        switch model.stylist {
        case .idle:
            VStack(alignment: .leading, spacing: 12) {
                Label("Ask the stylist", systemImage: "sparkles")
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.ink)
                Text(
                    "Claude weighs a dozen options for color, proportion and occasion, then explains its picks."
                )
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
                Button("Get stylist picks") { askStylist() }
                    .buttonStyle(.pill(.accent))
            }
            .card()
        case .loading:
            HStack(spacing: 12) {
                ProgressView().tint(Theme.terracotta)
                Text("The stylist is looking through your closet…")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
            }
            .card()
        case let .picked(picks):
            SectionTitle(text: "Stylist picks")
            ForEach(picks, id: \.outfit.id) { pick in
                card(for: pick.outfit, image: image, isSaved: savedIDs.contains(pick.outfit.id), reason: pick.reason)
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message).font(.callout).foregroundStyle(Theme.terracotta)
                Button("Try again") { askStylist() }
                    .buttonStyle(.pill(.quiet))
            }
            .card()
        }
    }

    private func askStylist() {
        Task { await model.askStylist(closet: closet, profile: profile) }
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

private struct WeatherCard: View {
    let state: TodayModel.WeatherState
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.sageInk)
                .frame(width: 48, height: 48)
                .background(Theme.sage, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(Theme.title(17))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
            if case .failed = state {
                Button("Retry", action: onRetry)
                    .buttonStyle(.pill(.quiet))
            }
        }
        .card()
    }

    private var symbol: String {
        switch state {
        case let .loaded(forecast): forecast.precipitationChance >= 0.5 ? "cloud.rain" : "sun.max"
        case .failed: "location.slash"
        case .idle, .loading: "cloud.sun"
        }
    }

    private var headline: String {
        switch state {
        case let .loaded(forecast): "\(Int(forecast.feelsLikeNowC.rounded()))° now"
        case .failed: "No weather"
        case .idle, .loading: "Checking the weather…"
        }
    }

    private var detail: String {
        switch state {
        case let .loaded(forecast):
            let low = Int(forecast.feelsLikeMinC.rounded())
            let high = Int(forecast.feelsLikeMaxC.rounded())
            let rain = Int((forecast.precipitationChance * 100).rounded())
            return "Feels \(low)–\(high)° today · \(rain)% chance of rain"
        case let .failed(message): return message
        case .idle, .loading: return "Using your approximate location"
        }
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
