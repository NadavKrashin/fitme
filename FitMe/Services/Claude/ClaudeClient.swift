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
    /// Non-2xx response. `type` is the API's error type, e.g. `rate_limit_error`.
    case api(status: Int, type: String?, message: String?)
    case refusal(category: String?)
    case truncated
    case noTextOutput
    case invalidResponse

    /// 429, 5xx and 529 (overloaded) are worth retrying later; everything else needs a change first.
    var isRetryable: Bool {
        guard case let .api(status, _, _) = self else { return false }
        return status == 429 || status >= 500
    }

    var userMessage: String {
        switch self {
        case .missingAPIKey:
            "Add your Claude API key in Settings to tag items automatically."
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

/// Minimal Messages API client: one request, one response, structured JSON output.
///
/// Swift has no official Anthropic SDK, so this speaks the documented HTTP API directly.
struct ClaudeClient: Sendable {
    // Statically valid literal; cannot fail.
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    /// Opt-in server-side fallback: a request declined by the model's safety classifiers is re-run on a
    /// recommended fallback model instead of failing.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    let apiKey: @Sendable () throws -> String?
    let transport: any HTTPTransport

    /// Sends one user turn and returns the model's JSON text output.
    func structuredOutput(
        model: String,
        effort: String,
        system: String,
        content: [ContentBlock],
        schema: JSONValue,
        maxTokens: Int = 16000
    ) async throws -> String {
        let request = MessagesRequest(
            model: model,
            maxTokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: content)],
            outputConfig: .init(effort: effort, format: OutputFormat(type: "json_schema", schema: schema)),
            fallbacks: "default"
        )
        let response = try await send(request)

        switch response.stopReason {
        case "refusal": throw ClaudeError.refusal(category: response.stopDetails?.category)
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }
        let text = response.content.compactMap(\.text).joined()
        guard !text.isEmpty else { throw ClaudeError.noTextOutput }
        return text
    }

    func send(_ body: MessagesRequest) async throws -> MessagesResponse {
        guard let key = try apiKey(), !key.isEmpty else { throw ClaudeError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        // Sorted keys keep the schema byte-identical across requests, so the API's compiled-schema cache hits.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await transport.send(request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw ClaudeError.api(status: http.statusCode, type: error?.error.type, message: error?.error.message)
        }
        do {
            return try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw ClaudeError.invalidResponse
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
