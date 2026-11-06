import FitEngine
import Foundation
import Testing
@testable import FitMe

struct TaggingServiceTests {
    private static let validJSON = """
    {"name":"Navy chinos","category":"bottom","subcategory":"chinos","pattern":"solid","formality":3,"warmth":2,
     "fit":"regular","isStatement":false,"styleTags":["classic"],"waterResistant":false}
    """

    @Test func schemaCoversEveryEngineCaseAndRequiresAllFields() throws {
        let data = try JSONEncoder().encode(ClaudeTaggingService.schema)
        let schema = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: [String: Any]])

        #expect(properties["category"]?["enum"] as? [String] == ItemCategory.allCases.map(\.rawValue))
        #expect(properties["pattern"]?["enum"] as? [String] == ItemPattern.allCases.map(\.rawValue))
        #expect(properties["fit"]?["enum"] as? [String] == Fit.allCases.map(\.rawValue))
        #expect(properties["formality"]?["enum"] as? [Int] == [1, 2, 3, 4, 5])
        #expect(Set(schema["required"] as? [String] ?? []) == Set(properties.keys))
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test func decodesValidTags() throws {
        let tags = try ClaudeTaggingService.decode(Self.validJSON)
        #expect(tags.category == .bottom)
        #expect(tags.styleTags == [.classic])
        let item = tags.item(id: "x", colors: [ItemColor(hex: "#27324A")])
        #expect(item.name == "Navy chinos")
        #expect(item.subcategory == "chinos")
        #expect(item.formality == 3)
    }

    @Test(arguments: [
        #"{"name":"x"}"#, // missing fields
        validJSON.replacingOccurrences(of: #""formality":3"#, with: #""formality":9"#), // out of range
        "not json",
    ])
    func rejectsInvalidTags(json: String) {
        #expect(throws: TaggingError.invalidTags) { try ClaudeTaggingService.decode(json) }
    }

    @Test func tagsAPhotoEndToEndWithoutNetwork() async throws {
        let transport = RecordingTransport(body: messagesResponse(text: Self.validJSON))
        let service = ClaudeTaggingService(client: ClaudeClient(apiKey: { "sk-test" }, transport: transport))

        let tags = try await service.tags(forJPEG: Data([0xFF, 0xD8]))

        #expect(tags.name == "Navy chinos")
        let body = try #require(await transport.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == ClaudeTaggingService.model)
    }

    @Test func blankNameFallsBackToSubcategory() {
        var tags = ItemTags.blank
        tags.subcategory = "denim jacket"
        #expect(tags.item(id: "x", colors: []).name == "Denim Jacket")
    }
}
