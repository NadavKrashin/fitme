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

    /// The stylist judges dress code, weight, fabric and style the way the engine does, so it needs them.
    @Test func briefDescribesEachPieceFully() {
        var item = Item(
            id: "x", name: "Navy crewneck sweater", category: .top, colors: [ItemColor(hex: "#22304D")],
            pattern: .textured, formality: 3, warmth: 3, styleTags: [.classic, .minimal]
        )
        item.fabric = .wool
        let line = ClaudeStylist.describe(item)
        #expect(line.contains("smart casual dress code"), "\(line)")
        #expect(line.contains("medium warmth"), "\(line)")
        #expect(line.contains("wool"), "\(line)")
        #expect(line.contains("classic, minimal style"), "\(line)")
    }

    @Test func briefMentionsADayThatSwings() throws {
        let options = try candidates(2)
        let context = OutfitContext(occasion: .casual, weather: Weather(feelsLikeC: 21, dayRange: 12 ... 27))
        let brief = ClaudeStylist.brief(candidates: options, context: context)
        #expect(brief.contains("Feels 12–27°C over the rest of the day"), "\(brief)")
    }

    @Test func briefPassesOnTheColorMood() throws {
        let options = try candidates(2)
        let neutral = OutfitContext(occasion: .casual, palette: .neutral)
        let colorful = OutfitContext(occasion: .casual, palette: .colorful)

        #expect(ClaudeStylist.brief(candidates: options, context: neutral).contains("Color: keep it neutral."))
        #expect(ClaudeStylist.brief(candidates: options, context: colorful).contains("Color: in the mood for color."))
        #expect(!ClaudeStylist.brief(candidates: options, context: OutfitContext(occasion: .casual)).contains("Color:"))
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
