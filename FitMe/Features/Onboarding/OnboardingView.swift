import SwiftUI

/// The first run: what FitMe does, the AI question, the weather, and the first clothes.
struct OnboardingView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AIConsentModel.self) private var consent
    @Environment(AppNavigation.self) private var navigation
    @State private var isLocating = false
    /// Room for a row's icon, growing with the text size so large icons don't overlap the text.
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 28

    var body: some View {
        Group {
            switch onboarding.step {
            case .welcome: welcome
            case .ai: AIConsentView { allowed in
                    consent.answer(allowed: allowed)
                    onboarding.advance()
                }
            case .weather: weather
            case .closet: closet
            }
        }
        .animation(.easeInOut(duration: 0.25), value: onboarding.step)
        .background(Theme.canvas)
        .tint(Theme.terracotta)
    }

    // MARK: Steps

    private var welcome: some View {
        page(
            symbol: "hanger",
            title: "Welcome to FitMe",
            message: "Your clothes, in one place, and the outfits they make.",
            points: [
                Point(
                    symbol: "camera",
                    title: "Photograph your closet",
                    detail: "Item after item; each one is cut out and tagged."
                ),
                Point(
                    symbol: "sun.max",
                    title: "Dress for the day",
                    detail: "Outfits for the weather, the occasion and your taste."
                ),
                Point(
                    symbol: "suitcase",
                    title: "Pack less",
                    detail: "The fewest pieces that dress every day of a trip."
                ),
            ]
        ) {
            Button("Get started") { onboarding.advance() }
                .buttonStyle(.pill(.primary))
        }
    }

    private var weather: some View {
        page(
            symbol: "cloud.sun",
            title: "Dressed for the weather",
            message: "FitMe uses your approximate location, rounded to about 1 km, to get today's weather. Without "
                + "it, you set the temperature yourself.",
            points: []
        ) {
            Button {
                isLocating = true
                Task {
                    // Asks for permission, then warms up today's forecast; a refusal is fine.
                    _ = try? await dependencies.weather.forecastHere()
                    isLocating = false
                    onboarding.advance()
                }
            } label: {
                if isLocating {
                    ProgressView().tint(Theme.onTerracotta)
                } else {
                    Text("Use my location")
                }
            }
            .buttonStyle(.pill(.primary))
            .disabled(isLocating)
            Button("Not now") { onboarding.advance() }
                .buttonStyle(.pill(.quiet))
                .disabled(isLocating)
        }
    }

    private var closet: some View {
        page(
            symbol: "camera",
            title: "Start your closet",
            message: consent.isAllowed
                ? "Photograph your clothes one after another, or choose photos you already have. Each one is cut out "
                + "and tagged for you to check. Plain backgrounds work best."
                : "Photograph your clothes one after another, or choose photos you already have. Each one is cut out "
                + "for you to tag. Plain backgrounds work best.",
            points: []
        ) {
            Button("Take photos") { start(.camera) }
                .buttonStyle(.pill(.primary))
            Button("Choose from library") { start(.library) }
                .buttonStyle(.pill(.quiet))
            Button("Later") { onboarding.finish() }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)
        }
    }

    private func start(_ source: AddSource) {
        onboarding.finish()
        navigation.addClothes(source)
    }

    // MARK: Layout

    private struct Point {
        let symbol: String
        let title: String
        let detail: String
    }

    private func page(
        symbol: String,
        title: String,
        message: String,
        points: [Point],
        @ViewBuilder actions: () -> some View
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.terracotta)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .foregroundStyle(Theme.inkMuted)
                ForEach(points, id: \.title) { point in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: point.symbol)
                            .font(.title3)
                            .foregroundStyle(Theme.terracotta)
                            .frame(width: iconWidth)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.title).font(.headline).foregroundStyle(Theme.ink)
                            Text(point.detail).font(.subheadline).foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                actions()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
            .background(Theme.canvas)
        }
    }
}
