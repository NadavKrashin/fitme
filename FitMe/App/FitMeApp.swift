import SwiftData
import SwiftUI

@main
struct FitMeApp: App {
    private let dependencies = AppDependencies.live()
    private let container: ModelContainer
    @State private var capture: CaptureModel
    @State private var consent: AIConsentModel

    init() {
        Theme.applyNavigationBarAppearance()
        let container: ModelContainer
        do {
            container = try Persistence.makeContainer()
        } catch {
            // Without its store the app can't show or save anything; crash with the cause rather than limp on.
            fatalError("Couldn't open the closet store: \(error)")
        }
        self.container = container
        _consent = State(initialValue: AIConsentModel(store: dependencies.aiConsent))
        _capture = State(initialValue: CaptureModel(
            processor: dependencies.photoProcessor,
            tagger: dependencies.tagger,
            transport: URLSession.shared,
            context: container.mainContext
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.dependencies, dependencies)
                .environment(capture)
                .environment(consent)
                .task { await capture.resumePending() }
        }
        .modelContainer(container)
    }
}
