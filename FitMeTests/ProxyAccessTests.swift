import CryptoKit
import Foundation
import Testing
@testable import FitMe

/// App Attest as the app sees it, with the device's attest service and the proxy faked.
struct ProxyAccessTests {
    private let base = URL(string: "https://proxy.test")!
    private let challenge = Data("server challenge".utf8).base64EncodedString()

    private func proxy(
        _ transport: ScriptedTransport,
        attest: FakeAppAttest,
        secrets: InMemorySecretStore
    ) -> ClaudeClient {
        ClaudeClient(
            access: ProxyAccess(base: base, attest: attest, secrets: secrets, transport: transport),
            transport: transport
        )
    }

    private func call(_ client: ClaudeClient) async throws -> String {
        try await client.structuredOutput(StructuredRequest(
            feature: .stylist,
            model: "claude-opus-5-5",
            effort: "medium",
            system: "Pick.",
            content: [.text("A or B")],
            schema: .object(["type": .string("object")])
        ))
    }

    @Test func attestsOnceThenSignsEveryRequest() async throws {
        let transport = ScriptedTransport([
            "/v1/attest/challenge": [(200, #"{"challenge":"\#(challenge)"}"#)],
            "/v1/attest": [(204, "")],
            "/v1/messages": [(200, messagesResponse(text: "{}")), (200, messagesResponse(text: "{}"))],
        ])
        let attest = FakeAppAttest()
        let secrets = InMemorySecretStore()
        let client = proxy(transport, attest: attest, secrets: secrets)

        _ = try await call(client)
        _ = try await call(client)

        #expect(await transport.paths == ["/v1/attest/challenge", "/v1/attest", "/v1/messages", "/v1/messages"])
        #expect(try secrets.read(.appAttestKeyID) == "key-1")
        let registration = try #require(await transport.requests[1].httpBody)
        let fields = try JSONDecoder().decode([String: String].self, from: registration)
        #expect(fields["keyId"] == "key-1")
        #expect(fields["challenge"] == challenge)
        #expect(await attest.attestedHashes == [Data(SHA256.hash(data: Data("server challenge".utf8)))])

        let message = await transport.requests[2]
        #expect(message.value(forHTTPHeaderField: "x-fitme-key-id") == "key-1")
        #expect(message.value(forHTTPHeaderField: "x-fitme-feature") == "stylist")
        #expect(message.value(forHTTPHeaderField: "x-api-key") == nil)
        // The assertion signs exactly the body that was sent.
        let body = try #require(message.httpBody)
        #expect(await attest.assertedHashes.first == Data(SHA256.hash(data: body)))
    }

    @Test func attestsAgainWhenTheProxyForgotTheDevice() async throws {
        let forgotten = #"{"type":"error","error":{"type":"attestation_failed","message":"Attest again."}}"#
        let transport = ScriptedTransport([
            "/v1/attest/challenge": [(200, #"{"challenge":"\#(challenge)"}"#)],
            "/v1/attest": [(204, "")],
            "/v1/messages": [(401, forgotten), (200, messagesResponse(text: "{}"))],
        ])
        let secrets = InMemorySecretStore()
        try secrets.write("old-key", for: .appAttestKeyID)

        _ = try await call(proxy(transport, attest: FakeAppAttest(), secrets: secrets))

        #expect(await transport.paths == ["/v1/messages", "/v1/attest/challenge", "/v1/attest", "/v1/messages"])
        #expect(try secrets.read(.appAttestKeyID) == "key-1")
    }

    @Test func withoutAppAttestAnInstallIDStandsIn() async throws {
        let transport = ScriptedTransport(["/v1/messages": [
            (200, messagesResponse(text: "{}")),
            (200, messagesResponse(text: "{}")),
        ]])
        let secrets = InMemorySecretStore()
        let client = proxy(transport, attest: FakeAppAttest(isSupported: false), secrets: secrets)

        _ = try await call(client)
        _ = try await call(client)

        let ids = await transport.requests.map { $0.value(forHTTPHeaderField: "x-fitme-install-id") }
        #expect(ids[0] != nil && ids[0] == ids[1])
        #expect(await transport.requests[0].value(forHTTPHeaderField: "x-fitme-key-id") == nil)
    }

    @Test func productionWithoutAProxyIsUnavailable() {
        #expect(ClaudeAccessKind.choose(proxyURL: nil, environment: .production) == .unavailable)
        #expect(ClaudeAccessKind.choose(proxyURL: nil, environment: .staging) == .ownKey)
        #expect(ClaudeAccessKind.choose(proxyURL: base, environment: .production) == .proxy)
    }
}
