import Foundation
import Testing
@testable import FitMe

@MainActor
struct OnboardingTests {
    private final class Flag: OnboardingStoring, @unchecked Sendable {
        // Unchecked: tests touch it from one task at a time.
        var done = false

        func isDone() -> Bool {
            done
        }

        func markDone() {
            done = true
        }
    }

    @Test func aNewUserWalksThroughEachStepOnce() {
        let flag = Flag()
        let model = OnboardingModel(store: flag, alreadySetUp: false)
        #expect(!model.isDone)
        #expect(model.step == .welcome)
        model.advance()
        #expect(model.step == .ai)
        model.advance()
        model.advance()
        #expect(model.step == .closet)
        model.advance()
        #expect(model.isDone)
        #expect(OnboardingModel(store: flag, alreadySetUp: false).isDone)
    }

    /// Someone with clothes, or who already answered the AI question, used FitMe before onboarding existed.
    @Test func existingUsersSkipIt() {
        let flag = Flag()
        #expect(OnboardingModel(store: flag, alreadySetUp: true).isDone)
        #expect(flag.done)
    }

    @Test func addingClothesFromAnywhereOpensTheCloset() {
        let navigation = AppNavigation()
        navigation.addClothes(.camera)
        #expect(navigation.tab == .closet)
        #expect(navigation.addRequest == .camera)
    }

    @Test func storedInUserDefaults() {
        let suite = "OnboardingTests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(!UserDefaultsOnboarding(suiteName: suite).isDone())
        UserDefaultsOnboarding(suiteName: suite).markDone()
        #expect(UserDefaultsOnboarding(suiteName: suite).isDone())
    }
}
