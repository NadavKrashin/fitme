import Foundation
import Testing
@testable import FitMe

struct ClaudeClientTests {
    private func client(_ transport: RecordingTransport, key: String? = "sk-test") -> ClaudeClient {
        ClaudeClient(apiKey: { key }, transport: transport)
    }

    private func call(_ client: ClaudeClient) async throws -> String {
        try await client.structuredOutput(
            model: "claude-opus-5-5",
            effort: "low",
            system: "Describe it.",
            content: [.jpeg(Data([0xFF, 0xD8])), .text("Tag this item.")],
            schema: .object(["type": .string("object")])
        )
    }

    @Test func sendsTheDocumentedRequestShape() async throws {
        let transport = RecordingTransport(body: messagesResponse(text: "{}"))
        _ = try await call(client(transport))

        let request = try #require(await transport.requests.first)
        #expect(request.url == ClaudeClient.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == ClaudeClient.apiVersion)
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == ClaudeClient.fallbackBeta)

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "claude-opus-5-5")
        #expect(json["max_tokens"] as? Int == 16000)
        #expect(json["fallbacks"] as? String == "default")
        let outputConfig = try #require(json["output_config"] as? [String: Any])
        #expect(outputConfig["effort"] as? String == "low")
        #expect((outputConfig["format"] as? [String: Any])?["type"] as? String == "json_schema")

        let message = try #require((json["messages"] as? [[String: Any]])?.first)
        #expect(message["role"] as? String == "user")
        let blocks = try #require(message["content"] as? [[String: Any]])
        #expect(blocks.map { $0["type"] as? String } == ["image", "text"])
        let source = try #require(blocks[0]["source"] as? [String: Any])
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "image/jpeg")
        #expect(source["data"] as? String == "/9g=")
    }

    @Test func returnsTheTextBlockAndIgnoresThinking() async throws {
        let transport = RecordingTransport(body: messagesResponse(text: #"{"name":"Tee"}"#))
        #expect(try await call(client(transport)) == #"{"name":"Tee"}"#)
    }

    @Test func refusalIsAnError() async {
        let body = #"{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}}"#
        await #expect(throws: ClaudeError.refusal(category: "cyber")) {
            try await call(client(RecordingTransport(body: body)))
        }
    }

    @Test func truncatedOutputIsAnError() async {
        let transport = RecordingTransport(body: messagesResponse(text: "{\"na", stopReason: "max_tokens"))
        await #expect(throws: ClaudeError.truncated) { try await call(client(transport)) }
    }

    @Test func apiErrorsCarryStatusAndType() async {
        let body = #"{"type":"error","error":{"type":"rate_limit_error","message":"Slow down"},"request_id":"req_1"}"#
        let error = await #expect(throws: ClaudeError.self) {
            try await call(client(RecordingTransport(status: 429, body: body)))
        }
        #expect(error == .api(status: 429, type: "rate_limit_error", message: "Slow down"))
        #expect(error?.isRetryable == true)
        #expect(ClaudeError.api(status: 400, type: "invalid_request_error", message: nil).isRetryable == false)
        #expect(ClaudeError.api(status: 529, type: "overloaded_error", message: nil).isRetryable == true)
    }

    @Test func missingKeyFailsWithoutSending() async {
        let transport = RecordingTransport(body: messagesResponse(text: "{}"))
        await #expect(throws: ClaudeError.missingAPIKey) { try await call(client(transport, key: nil)) }
        #expect(await transport.requests.isEmpty)
    }
}
