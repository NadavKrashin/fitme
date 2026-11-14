import Foundation

/// Sends HTTP requests. `URLSession` in the app; a recorder in tests.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

enum ClaudeError: Error, Equatable {
    case missingAPIKey
    /// This build has no way to reach Claude (a production build without a proxy configured).
    case unavailable
    /// Non-2xx response. `type` is the API's error type, e.g. `rate_limit_error`.
    case api(status: Int, type: String?, message: String?)
    case refusal(category: String?)
    case truncated
    case noTextOutput
    case invalidResponse

    /// The proxy's answers that waiting a moment won't change: the month's allowance, a pause, today's cap, an
    /// install it can't verify.
    static let proxyLimits: Set<String> = [
        "allowance_exceeded", "ai_paused", "daily_cap", "attestation_failed", "attestation_required",
    ]

    /// 429, 5xx and 529 (overloaded) are worth retrying later; everything else needs a change first.
    var isRetryable: Bool {
        guard case let .api(status, type, _) = self, !Self.proxyLimits.contains(type ?? "") else { return false }
        return status == 429 || status >= 500
    }

    var userMessage: String {
        switch self {
        case .missingAPIKey:
            "Add your Claude API key in Settings to use Claude."
        case .unavailable:
            "Claude isn't set up in this version of FitMe. You can still tag by hand."
        case .api(_, "allowance_exceeded"?, _):
            "You've used this month's AI allowance. It resets on the 1st; you can still tag by hand."
        case .api(_, "ai_paused"?, _):
            "FitMe's AI features are paused for now. You can still tag by hand."
        case .api(_, "daily_cap"?, _):
            "FitMe's AI is at capacity for today. Try again tomorrow, or tag by hand."
        case .api(_, "attestation_failed"?, _), .api(_, "attestation_required"?, _):
            "This copy of FitMe couldn't be verified, so Claude isn't available on it."
        case let .api(status, _, _) where status == 401:
            "Claude rejected the API key. Check it in Settings."
        case .api where isRetryable:
            "Claude is busy right now. Try again in a moment."
        case let .api(_, _, message):
            "Claude couldn't process this photo\(message.map { ": \($0)" } ?? ".")"
        case .refusal:
            "Claude declined to describe this photo. Tag it by hand."
        case .truncated, .noTextOutput, .invalidResponse:
            "Claude returned an unusable answer. Try again or tag it by hand."
        }
    }
}

/// One structured-output request: a single user turn for one feature, answered as JSON matching `schema`.
struct StructuredRequest {
    let feature: ClaudeFeature
    let model: String
    let effort: String
    let system: String
    let content: [ContentBlock]
    let schema: JSONValue
    var maxTokens = 16000
}

/// Minimal Messages API client: one request, one response, structured JSON output. Where requests go, and how
/// they're authorized, is `access`: FitMe's proxy, or the user's own key.
///
/// Swift has no official Anthropic SDK, so this speaks the documented HTTP API directly.
struct ClaudeClient: Sendable {
    let access: any ClaudeAccess
    let transport: any HTTPTransport

    /// Sends one user turn and returns the model's JSON text output.
    func structuredOutput(_ ask: StructuredRequest) async throws -> String {
        let request = MessagesRequest(
            model: ask.model,
            maxTokens: ask.maxTokens,
            system: ask.system,
            messages: [.init(role: "user", content: ask.content)],
            outputConfig: .init(effort: ask.effort, format: OutputFormat(type: "json_schema", schema: ask.schema)),
            fallbacks: "default"
        )
        let response = try await send(request, feature: ask.feature)

        switch response.stopReason {
        case "refusal": throw ClaudeError.refusal(category: response.stopDetails?.category)
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }
        let text = response.content.compactMap(\.text).joined()
        guard !text.isEmpty else { throw ClaudeError.noTextOutput }
        return text
    }

    func send(_ body: MessagesRequest, feature: ClaudeFeature) async throws -> MessagesResponse {
        // Sorted keys keep the schema byte-identical across requests, so the API's compiled-schema cache hits.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(body)
        do {
            return try await post(data, feature: feature)
        } catch let error as ClaudeError {
            // The proxy lost this device's key (or it was reset): attest again, once.
            guard case .api(401, "attestation_failed"?, _) = error, await access.forgetDevice() else { throw error }
            return try await post(data, feature: feature)
        }
    }

    private func post(_ body: Data, feature: ClaudeFeature) async throws -> MessagesResponse {
        var request = URLRequest(url: access.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(feature.rawValue, forHTTPHeaderField: "x-fitme-feature")
        for (name, value) in try await access.headers(for: body) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body

        let (data, response) = try await transport.send(request)
        try Self.check(data, response)
        do {
            return try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw ClaudeError.invalidResponse
        }
    }

    /// Throws the API's (or the proxy's, which uses the same shape) error for a non-2xx response.
    static func check(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw ClaudeError.api(status: http.statusCode, type: error?.error.type, message: error?.error.message)
        }
    }
}

// MARK: - Wire types

struct MessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [ContentBlock]
    }

    struct OutputConfig: Encodable {
        let effort: String
        let format: OutputFormat
    }

    let model: String
    let maxTokens: Int
    let system: String
    let messages: [Message]
    let outputConfig: OutputConfig
    let fallbacks: String

    private enum CodingKeys: String, CodingKey {
        case model, system, messages, fallbacks
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }
}

/// A user content block: an image or text.
enum ContentBlock: Encodable {
    case jpeg(Data)
    case text(String)

    private enum CodingKeys: String, CodingKey { case type, source, text }
    private enum SourceKeys: String, CodingKey { case type, mediaType = "media_type", data }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .jpeg(data):
            try container.encode("image", forKey: .type)
            var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode("image/jpeg", forKey: .mediaType)
            try source.encode(data.base64EncodedString(), forKey: .data)
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

struct OutputFormat: Encodable {
    let type: String
    let schema: JSONValue
}

struct MessagesResponse: Decodable {
    struct Block: Decodable {
        let type: String
        /// Set on `text` blocks; thinking and fallback blocks are ignored.
        let text: String?
    }

    struct StopDetails: Decodable {
        let category: String?
    }

    let content: [Block]
    let stopReason: String?
    let stopDetails: StopDetails?

    private enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case stopDetails = "stop_details"
    }
}

private struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        let type: String
        let message: String
    }

    let error: Detail
}

/// Arbitrary JSON, for schemas built in code.
indirect enum JSONValue: Encodable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}
