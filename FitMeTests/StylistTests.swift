import FitEngine
import Foundation
import Testing
@testable import FitMe

struct StylistTests {
    private func candidates(_ count: Int) throws -> [ScoredOutfit] {
        let generator = OutfitGenerator()
        let outfits = try generator.suggest(
            from: DemoCloset.items(),
            context: OutfitContext(occasion: .casual),
            limit: count
        )
        try #require(outfits.count == count)
        return outfits
    }

    @Test func mapsLabelsBackToCandidatesAndDropsTheRest() throws {
        let options = try candidates(4)
        let labeled = Dictionary(uniqueKeysWithValues: zip(ClaudeStylist.labels, options))
        let json = """
        {"picks":[{"candidate":"C","why":"Best."},{"candidate":"C","why":"Again."},{"candidate":"Q","why":"Invented."},
                  {"candidate":"A","why":"Good."},{"candidate":"B","why":"Fine."},{"candidate":"D","why":"Extra."}]}
        """

        let picks = try ClaudeStylist.decode(json, labeled: labeled)

        #expect(picks.map(\.outfit) == [options[2], options[0], options[1]])
        #expect(picks.first?.reason == "Best.")
    }

    @Test func noUsablePicksIsAnError() throws {
        let labeled = try Dictionary(uniqueKeysWithValues: zip(ClaudeStylist.labels, candidates(2)))
        #expect(throws: ClaudeError.invalidResponse) {
            try ClaudeStylist.decode(#"{"picks":[{"candidate":"Z","why":"?"}]}"#, labeled: labeled)
        }
    }

    @Test func briefDescribesOccasionWeatherAndEachCandidate() throws {
        let options = try candidates(3)
        let context = OutfitContext(occasion: .date, weather: Weather(feelsLikeC: 9.4, precipitationChance: 0.8))

        let brief = ClaudeStylist.brief(candidates: options, context: context)

        #expect(brief.contains("Occasion: Date."))
        #expect(brief.contains("Feels like 9°C, rain likely."))
        #expect(brief.contains("A: "))
        #expect(brief.contains("C: "))
        #expect(!brief.contains("D: "))
    }

    @Test func schemaOnlyAllowsTheGivenLabels() throws {
        let data = try JSONEncoder().encode(ClaudeStylist.schema(labels: ["A", "B"]))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains(#""enum":["A","B"]"#))
    }

    @Test func picksEndToEndWithoutNetwork() async throws {
        let options = try candidates(3)
        let transport =
            RecordingTransport(body: messagesResponse(text: #"{"picks":[{"candidate":"B","why":"Balanced."}]}"#))
        let stylist = ClaudeStylist(client: ClaudeClient(apiKey: { "sk-test" }, transport: transport))

        let picks = try await stylist.pick(from: options, context: OutfitContext(occasion: .casual))

        #expect(picks == [StylistPick(outfit: options[1], reason: "Balanced.")])
    }

    @Test(arguments: [
        ("#1F2A44", "navy"), ("#1A1A1A", "black"), ("#9A9A9A", "grey"), ("#C19A6B", "camel"),
        ("#C3B091", "khaki"), ("#5B6236", "olive"), ("#D8C7A8", "beige"), ("#B3262E", "red"), ("#2F7D3A", "green"),
    ])
    func colorNames(hex: String, expected: String) {
        #expect(ItemColor(hex: hex).name == expected)
    }
}
