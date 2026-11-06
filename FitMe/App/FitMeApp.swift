import SwiftData
import SwiftUI

@main
struct FitMeApp: App {
    private let dependencies = AppDependencies.live()
    private let container: ModelContainer
    @State private var capture: CaptureModel

    init() {
        let container: ModelContainer
        do {
            container = try Persistence.makeContainer()
        } catch {
            // Without its store the app can't show or save anything; crash with the cause rather than limp on.
            fatalError("Couldn't open the closet store: \(error)")
        }
        self.container = container
        _capture = State(initialValue: CaptureModel(
            processor: dependencies.photoProcessor,
            tagger: dependencies.tagger,
            context: container.mainContext
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.dependencies, dependencies)
                .environment(capture)
                .task { await capture.resumePending() }
        }
        .modelContainer(container)
    }
}
