import SwiftData
import SwiftUI

@main
struct FitMeApp: App {
    private let dependencies = AppDependencies.live()
    private let container: ModelContainer
    @State private var capture: CaptureModel
    @State private var consent: AIConsentModel
    @State private var onboarding: OnboardingModel
    @State private var navigation = AppNavigation()

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
        // People who used FitMe before onboarding existed skip it.
        let hasClothes = ((try? container.mainContext.fetchCount(FetchDescriptor<ItemRecord>())) ?? 0) > 0
        _onboarding = State(initialValue: OnboardingModel(
            store: UserDefaultsOnboarding(),
            alreadySetUp: hasClothes || dependencies.aiConsent.read() != .notAsked
        ))
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
                .environment(onboarding)
                .environment(navigation)
                .task { await capture.resumePending() }
        }
        .modelContainer(container)
    }
}
