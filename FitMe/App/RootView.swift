import SwiftUI

struct RootView: View {
    @Environment(AIConsentModel.self) private var consent

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            TripsView()
                .tabItem { Label("Trips", systemImage: "suitcase") }
            SavedView()
                .tabItem { Label("Saved", systemImage: "heart") }
            ClosetView()
                .tabItem { Label("Closet", systemImage: "hanger") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.terracotta)
        .toolbarBackground(Theme.card, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        // Asked once, before anything can go to Claude.
        .sheet(isPresented: .constant(consent.consent == .notAsked)) {
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
        .modelContainer(PreviewData.container)
}
#endif
