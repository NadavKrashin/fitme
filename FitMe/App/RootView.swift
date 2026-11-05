import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            ClosetView()
                .tabItem { Label("Closet", systemImage: "hanger") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .environment(\.dependencies, .preview())
        .modelContainer(PreviewData.container)
}
#endif
