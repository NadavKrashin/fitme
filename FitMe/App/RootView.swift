import SwiftUI

struct RootView: View {
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
    }
}

#if DEBUG
#Preview {
    RootView()
        .environment(\.dependencies, .preview())
        .environment(PreviewData.captureModel)
        .modelContainer(PreviewData.container)
}
#endif
