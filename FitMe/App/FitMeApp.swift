import SwiftData
import SwiftUI

@main
struct FitMeApp: App {
    private let dependencies = AppDependencies.live()
    private let container: ModelContainer

    init() {
        do {
            container = try Persistence.makeContainer()
        } catch {
            // Without its store the app can't show or save anything; crash with the cause rather than limp on.
            fatalError("Couldn't open the closet store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.dependencies, dependencies)
        }
        .modelContainer(container)
    }
}
