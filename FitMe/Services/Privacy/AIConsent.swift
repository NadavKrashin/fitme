import Foundation
import Observation

/// Whether the user lets FitMe send photos and closet details to Claude, Anthropic's AI. App Review guideline
/// 5.1.2(i): apps must say what personal data goes to a third-party AI, and get permission before sending it.
enum AIConsent: String, Sendable {
    case notAsked
    case allowed
    case declined
}

protocol AIConsentStoring: Sendable {
    func read() -> AIConsent
    func write(_ consent: AIConsent)
}

/// The choice in UserDefaults (the standard suite unless a test passes its own).
struct UserDefaultsAIConsent: AIConsentStoring {
    static let key = "aiConsent"
    var suiteName: String?

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func read() -> AIConsent {
        defaults.string(forKey: Self.key).flatMap(AIConsent.init(rawValue:)) ?? .notAsked
    }

    func write(_ consent: AIConsent) {
        defaults.set(consent.rawValue, forKey: Self.key)
    }
}

/// The choice as the UI sees it: asked once on first launch, changeable in Settings.
@MainActor
@Observable
final class AIConsentModel {
    private(set) var consent: AIConsent
    private let store: any AIConsentStoring

    init(store: any AIConsentStoring) {
        self.store = store
        consent = store.read()
    }

    var isAllowed: Bool {
        consent == .allowed
    }

    func answer(allowed: Bool) {
        consent = allowed ? .allowed : .declined
        store.write(consent)
    }
}

/// Lets a Claude request through only once the user has allowed it, whatever route it takes.
struct ConsentGatedAccess: ClaudeAccess {
    let inner: any ClaudeAccess
    let consent: any AIConsentStoring

    var endpoint: URL {
        inner.endpoint
    }

    func headers(for body: Data) async throws -> [String: String] {
        guard consent.read() == .allowed else { throw ClaudeError.consentNeeded }
        return try await inner.headers(for: body)
    }

    func forgetDevice() async -> Bool {
        await inner.forgetDevice()
    }
}

/// Where FitMe's privacy policy and support page live (GitHub Pages, built from `site/`).
enum PrivacyLinks {
    // Statically valid literals; cannot fail.
    static let policy = URL(string: "https://nadavkrashin.github.io/fitme/privacy.html")!
    static let support = URL(string: "https://nadavkrashin.github.io/fitme/support.html")!
}
