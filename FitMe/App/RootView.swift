import SwiftUI

struct RootView: View {
    @Environment(AIConsentModel.self) private var consent
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            TripsView()
                .tabItem { Label("Trips", systemImage: "suitcase") }
                .tag(AppTab.trips)
            SavedView()
                .tabItem { Label("Saved", systemImage: "heart") }
                .tag(AppTab.saved)
            ClosetView()
                .tabItem { Label("Closet", systemImage: "hanger") }
                .tag(AppTab.closet)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(Theme.terracotta)
        .toolbarBackground(Theme.card, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .fullScreenCover(isPresented: .constant(!onboarding.isDone)) {
            OnboardingView()
        }
        // Onboarding asks this; the sheet only covers a choice that went missing since.
        .sheet(isPresented: .constant(onboarding.isDone && consent.consent == .notAsked)) {
            AIConsentView { consent.answer(allowed: $0) }
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .environment(\.dependencies, .preview())
        .environment(PreviewData.captureModel)
        .environment(AIConsentModel(store: PreviewConsent()))
        .environment(PreviewData.onboardingDone)
        .environment(AppNavigation())
        .modelContainer(PreviewData.container)
}
#endif
