import FitEngine
import Foundation
import Testing
@testable import FitMe

struct TaggingServiceTests {
    private static let validJSON = """
    {"name":"Navy chinos","category":"bottom","subcategory":"chinos","pattern":"solid","formality":3,"warmth":2,
     "fit":"regular","isStatement":false,"styleTags":["classic"],"waterResistant":false,
     "itemBox":{"x0":120,"y0":80,"x1":880,"y1":960}}
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

    /// The engine's warmth rules (shorts from 20°, sweaters off from 24°, boots under 24°) assume one scale, the
    /// one the demo closet uses. The tagging rubric must put the same kinds of item at the same levels.
    @Test(arguments: [
        ("t-shirt", 1), ("polo", 1), ("linen", 1), ("shorts", 1), ("sandals", 1),
        ("oxford", 2), ("chinos", 2), ("sneakers", 2), ("loafers", 2), ("cardigan", 2), ("denim jacket", 2),
        ("rain shell", 2), ("sweater", 3), ("hoodie", 3), ("jeans", 3), ("fleece", 3), ("leather jacket", 3),
        ("trench", 3), ("boots", 4), ("heavy knit", 4), ("wool coat", 5), ("puffer", 5),
    ])
    func warmthRubricMatchesTheEngineScale(kind: String, level: Int) throws {
        let rubric = ClaudeTaggingService.systemPrompt
        let start = try #require(rubric.range(of: "- warmth: "))
        let line = rubric[start.upperBound...].prefix { $0 != "\n" }
        let levels = line.components(separatedBy: "), ")
        let entry = try #require(levels.first { $0.hasPrefix("\(level) ") }, "level \(level) in \(line)")
        #expect(entry.contains(kind), "\(kind) should be warmth \(level): \(entry)")
    }

    @Test func decodesValidTags() throws {
        let tagged = try ClaudeTaggingService.decode(Self.validJSON)
        #expect(tagged.itemBox == ItemBox(x0: 120, y0: 80, x1: 880, y1: 960))
        let tags = tagged.tags
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

        let tagged = try await service.tag(jpeg: Data([0xFF, 0xD8]), listing: nil)

        #expect(tagged.tags.name == "Navy chinos")
        let body = try #require(await transport.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == ClaudeTaggingService.model)
    }

    @Test(arguments: [
        #""itemBox":{"x0":900,"y0":80,"x1":100,"y1":960}"#, // inverted
        #""itemBox":{"x0":120,"y0":80,"x1":1400,"y1":960}"#, // out of range
    ])
    func invalidBoxIsDroppedButTagsAreKept(box: String) throws {
        let validBox = #""itemBox":{"x0":120,"y0":80,"x1":880,"y1":960}"#
        let tagged = try ClaudeTaggingService.decode(Self.validJSON.replacingOccurrences(of: validBox, with: box))
        #expect(tagged.itemBox == nil)
        #expect(tagged.tags.name == "Navy chinos")
    }

    @Test func blankNameFallsBackToSubcategory() {
        var tags = ItemTags.blank
        tags.subcategory = "denim jacket"
        #expect(tags.item(id: "x", colors: []).name == "Denim Jacket")
    }

    @Test func theShopListingIsSentBetweenThePhotoAndTheRequest() async throws {
        let transport = RecordingTransport(body: messagesResponse(text: Self.validJSON))
        let service = ClaudeTaggingService(client: ClaudeClient(apiKey: { "sk-test" }, transport: transport))

        _ = try await service.tag(jpeg: Data([0xFF, 0xD8]), listing: "Material: 100% merino")

        let body = try #require(await transport.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["image", "text", "text"])
        #expect(content[1]["text"] as? String == "The shop's listing for this item:\nMaterial: 100% merino")
    }
}
