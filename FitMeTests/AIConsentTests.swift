import Foundation
import Testing
@testable import FitMe

/// App Review 5.1.2(i): nothing goes to a third-party AI until the user allows it.
struct AIConsentTests {
    private final class Box: AIConsentStoring, @unchecked Sendable {
        // Unchecked: tests touch it from one task at a time.
        var value: AIConsent
        init(_ value: AIConsent) {
            self.value = value
        }

        func read() -> AIConsent {
            value
        }

        func write(_ consent: AIConsent) {
            value = consent
        }
    }

    private func call(_ consent: AIConsent) async throws -> RecordingTransport {
        let transport = RecordingTransport(body: messagesResponse(text: "{}"))
        let access = ConsentGatedAccess(inner: OwnKeyAccess(apiKey: { "sk-test" }), consent: Box(consent))
        _ = try await ClaudeClient(access: access, transport: transport).structuredOutput(StructuredRequest(
            feature: .tag,
            model: "claude-opus-5-5",
            effort: "low",
            system: "Tag it.",
            content: [.jpeg(Data([0xFF, 0xD8]))],
            schema: .object(["type": .string("object")])
        ))
        return transport
    }

    @Test(arguments: [AIConsent.notAsked, .declined])
    func nothingIsSentWithoutPermission(consent: AIConsent) async {
        await #expect(throws: ClaudeError.consentNeeded) { try await call(consent) }
    }

    @Test func allowedRequestsGoThrough() async throws {
        #expect(await try call(.allowed).requests.count == 1)
    }

    @Test @MainActor func theAnswerIsKept() {
        let store = Box(.notAsked)
        let model = AIConsentModel(store: store)
        #expect(model.consent == .notAsked)
        model.answer(allowed: true)
        #expect(store.value == .allowed)
        model.answer(allowed: false)
        #expect(AIConsentModel(store: store).consent == .declined)
    }

    @Test func storedInUserDefaults() {
        let suite = "AIConsentTests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = UserDefaultsAIConsent(suiteName: suite)
        #expect(store.read() == .notAsked)
        store.write(.allowed)
        #expect(UserDefaultsAIConsent(suiteName: suite).read() == .allowed)
    }

    @Test func turnedOffClaudeExplainsItself() {
        #expect(ClaudeError.consentNeeded.userMessage.contains("Settings"))
        #expect(!ClaudeError.consentNeeded.isRetryable)
    }
}
