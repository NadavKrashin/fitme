import CryptoKit
import Foundation

/// What a Claude request is for. The proxy counts each against its own monthly allowance.
enum ClaudeFeature: String, Sendable {
    case tag
    case stylist
    case bag
}

/// Where Claude requests go, and what proves they may go there.
protocol ClaudeAccess: Sendable {
    var endpoint: URL { get }
    /// Headers that authorize this exact request body: an API key, or an App Attest assertion over the body.
    func headers(for body: Data) async throws -> [String: String]
    /// The proxy no longer knows this device. Returns whether trying again (after re-attesting) can help.
    func forgetDevice() async -> Bool
}

/// How this build reaches Claude, for Settings to explain.
enum ClaudeAccessKind: Sendable {
    /// Through FitMe's proxy; nothing to set up.
    case proxy
    /// Straight to Anthropic with the user's own API key (Debug and Staging builds without a proxy).
    case ownKey
    /// A production build without a proxy configured.
    case unavailable

    static func choose(proxyURL: URL?, environment: AppEnvironment) -> ClaudeAccessKind {
        if proxyURL != nil {
            return .proxy
        }
        return environment == .production ? .unavailable : .ownKey
    }
}

/// Straight to Anthropic with the user's own key, entered in Settings.
struct OwnKeyAccess: ClaudeAccess {
    // Statically valid literal; cannot fail.
    static let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    /// Opt-in server-side fallback: a request declined by the model's safety classifiers is re-run on a
    /// recommended fallback model instead of failing.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    let apiKey: @Sendable () throws -> String?

    var endpoint: URL {
        Self.anthropicEndpoint
    }

    func headers(for _: Data) async throws -> [String: String] {
        guard let key = try apiKey(), !key.isEmpty else { throw ClaudeError.missingAPIKey }
        return ["x-api-key": key, "anthropic-version": Self.apiVersion, "anthropic-beta": Self.fallbackBeta]
    }

    func forgetDevice() async -> Bool {
        false
    }
}

/// A production build with no proxy: Claude features explain themselves and the rest of the app works.
struct UnavailableAccess: ClaudeAccess {
    /// Never contacted; any valid URL.
    let endpoint = OwnKeyAccess.anthropicEndpoint

    func headers(for _: Data) async throws -> [String: String] {
        throw ClaudeError.unavailable
    }

    func forgetDevice() async -> Bool {
        false
    }
}

/// FitMe's proxy (server/claude-proxy), which holds the API key. The device proves it's a genuine FitMe install with
/// App Attest: a key registered once, then a signature over every request body. Where App Attest isn't available
/// (the Simulator), a random install ID stands in; only the Staging proxy accepts that.
actor ProxyAccess: ClaudeAccess {
    nonisolated let endpoint: URL
    private let base: URL
    private let attest: any AppAttesting
    private let secrets: any SecretStore
    private let transport: any HTTPTransport
    private var registering: Task<String, Error>?

    init(base: URL, attest: any AppAttesting, secrets: any SecretStore, transport: any HTTPTransport) {
        self.base = base
        endpoint = base.appending(path: "v1/messages")
        self.attest = attest
        self.secrets = secrets
        self.transport = transport
    }

    func headers(for body: Data) async throws -> [String: String] {
        guard attest.isSupported else { return try ["x-fitme-install-id": installID()] }
        let keyID = try await registeredKey()
        let assertion = try await attest.generateAssertion(keyID, clientDataHash: Self.hash(body))
        return ["x-fitme-key-id": keyID, "x-fitme-assertion": assertion.base64EncodedString()]
    }

    func forgetDevice() async -> Bool {
        guard attest.isSupported else { return false }
        try? secrets.delete(.appAttestKeyID)
        return true
    }

    /// The registered key, registering one first if needed. Concurrent requests share one registration.
    private func registeredKey() async throws -> String {
        if let stored = try secrets.read(.appAttestKeyID) {
            return stored
        }
        if let registering {
            return try await registering.value
        }
        let task = Task { try await register() }
        registering = task
        defer { registering = nil }
        let keyID = try await task.value
        try secrets.write(keyID, for: .appAttestKeyID)
        return keyID
    }

    private func register() async throws -> String {
        let challenge = try await fetchChallenge()
        let keyID = try await attest.generateKey()
        let attestation = try await attest.attestKey(keyID, clientDataHash: Self.hash(challenge.bytes))
        var request = URLRequest(url: base.appending(path: "v1/attest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode([
            "keyId": keyID,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge.text,
        ])
        let (data, response) = try await transport.send(request)
        try ClaudeClient.check(data, response)
        return keyID
    }

    private func fetchChallenge() async throws -> (text: String, bytes: Data) {
        let (data, response) = try await transport.send(URLRequest(url: base.appending(path: "v1/attest/challenge")))
        try ClaudeClient.check(data, response)
        guard let text = try? JSONDecoder().decode([String: String].self, from: data)["challenge"],
              let bytes = Data(base64Encoded: text)
        else { throw ClaudeError.invalidResponse }
        return (text, bytes)
    }

    private func installID() throws -> String {
        if let stored = try secrets.read(.installID) {
            return stored
        }
        let id = UUID().uuidString
        try secrets.write(id, for: .installID)
        return id
    }

    private static func hash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
