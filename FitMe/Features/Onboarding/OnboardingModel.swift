import Foundation
import Observation

protocol OnboardingStoring: Sendable {
    func isDone() -> Bool
    func markDone()
}

/// Onboarding's "done" flag in UserDefaults (the standard suite unless a test passes its own).
struct UserDefaultsOnboarding: OnboardingStoring {
    static let key = "onboardingDone"
    var suiteName: String?

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func isDone() -> Bool {
        defaults.bool(forKey: Self.key)
    }

    func markDone() {
        defaults.set(true, forKey: Self.key)
    }
}

/// A first run in four steps: what FitMe does, the AI question, the weather (location asked only on a tap), and the
/// first clothes. Each permission is asked when its reason is on screen, never all at once on launch.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, ai, weather, closet
    }

    private(set) var isDone: Bool
    private(set) var step: Step = .welcome
    private let store: any OnboardingStoring

    /// `alreadySetUp`: someone who used FitMe before onboarding existed (clothes in the closet, or the AI question
    /// answered) doesn't see it.
    init(store: any OnboardingStoring, alreadySetUp: Bool) {
        self.store = store
        if alreadySetUp, !store.isDone() {
            store.markDone()
        }
        isDone = store.isDone()
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    func finish() {
        store.markDone()
        isDone = true
    }
}
