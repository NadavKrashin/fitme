import SwiftData
import SwiftUI

@main
struct FitMeApp: App {
    private let dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.dependencies, dependencies)
        }
        .modelContainer(for: ItemRecord.self)
    }
}
