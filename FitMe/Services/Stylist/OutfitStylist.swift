import FitEngine
import Foundation

struct StylistPick: Hashable, Sendable {
    let outfit: ScoredOutfit
    let reason: String
}

protocol OutfitStylist: Sendable {
    /// Picks and explains the best few of the engine's candidates. Never returns an outfit that wasn't a candidate.
    func pick(from candidates: [ScoredOutfit], context: OutfitContext) async throws -> [StylistPick]
}

/// Asks Claude to judge the engine's candidates like a stylist would, working from text descriptions: cheaper than
/// images, and it works for items without photos.
struct ClaudeStylist: OutfitStylist {
    static let model = "claude-opus-5-5"
    /// Taste needs a little more thought than tagging does.
    static let effort = "medium"
    static let maxPicks = 3

    let client: ClaudeClient

    func pick(from candidates: [ScoredOutfit], context: OutfitContext) async throws -> [StylistPick] {
        let labeled = Dictionary(uniqueKeysWithValues: zip(Self.labels, candidates))
        let json = try await client.structuredOutput(
            model: Self.model,
            effort: Self.effort,
            system: Self.systemPrompt,
            content: [.text(Self.brief(candidates: candidates, context: context))],
            schema: Self.schema(labels: Array(Self.labels.prefix(candidates.count)))
        )
        return try Self.decode(json, labeled: labeled)
    }

    /// "A", "B", ... Short labels keep the prompt small and give the schema a closed set to choose from.
    static let labels = (UnicodeScalar("A").value ... UnicodeScalar("Z").value).compactMap {
        UnicodeScalar($0).map(String.init)
    }

    static func decode(_ json: String, labeled: [String: ScoredOutfit]) throws -> [StylistPick] {
        guard let response = try? JSONDecoder().decode(StylistResponse.self, from: Data(json.utf8)) else {
            throw ClaudeError.invalidResponse
        }
        var seen = Set<String>()
        let picks = response.picks.compactMap { pick -> StylistPick? in
            guard let outfit = labeled[pick.candidate], seen.insert(pick.candidate).inserted else { return nil }
            return StylistPick(outfit: outfit, reason: pick.why)
        }
        guard !picks.isEmpty else { throw ClaudeError.invalidResponse }
        return Array(picks.prefix(maxPicks))
    }

    static let systemPrompt = """
    You are a personal stylist. The user is getting dressed from their own closet. You get candidate outfits that \
    already pass basic rules (weather, dress code); choose the ones that will genuinely look best together: color \
    harmony, proportion and fit, texture, and how well the outfit suits the occasion.

    Pick up to \(maxPicks), best first. For each, say in one short sentence why it works, in plain words the user \
    will act on (e.g. "The camel cardigan warms up the navy and echoes the loafers."). Never suggest items that \
    aren't listed.
    """

    static func brief(candidates: [ScoredOutfit], context: OutfitContext) -> String {
        let weather = context.weather
        var lines = [
            "Occasion: \(context.occasion.title).",
            "Feels like \(Int(weather.feelsLikeC.rounded()))°C\(weather.isRainy ? ", rain likely" : "").",
            "",
            "Candidates:",
        ]
        for (label, candidate) in zip(labels, candidates) {
            lines.append("\(label): " + candidate.outfit.items.map(describe).joined(separator: " + "))
        }
        return lines.joined(separator: "\n")
    }

    static func describe(_ item: Item) -> String {
        let colors = item.significantColors.map { "\($0.name) \($0.hex)" }.joined(separator: " and ")
        var details = [colors, item.pattern.title.lowercased(), "\(item.fit.rawValue) fit"]
        if item.isStatement {
            details.append("statement piece")
        }
        return "\(item.name) (\(item.category.title.lowercased()); \(details.joined(separator: ", ")))"
    }

    static func schema(labels: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "picks": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "candidate": .object([
                                "type": .string("string"),
                                "enum": .array(labels.map(JSONValue.string)),
                            ]),
                            "why": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("candidate"), .string("why")]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
            ]),
            "required": .array([.string("picks")]),
            "additionalProperties": .bool(false),
        ])
    }
}

private struct StylistResponse: Decodable {
    struct Pick: Decodable {
        let candidate: String
        let why: String
    }

    let picks: [Pick]
}
