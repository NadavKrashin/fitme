import FitEngine
import Foundation

/// A stylist's read on a packed bag: a short verdict, and a few changes the user can apply with one tap.
struct CapsuleReview: Hashable, Sendable {
    struct Change: Hashable, Identifiable, Sendable {
        /// A packed item to leave at home.
        var leaveOut: String?
        /// A closet item to bring instead (or as well).
        var bring: String?
        var why: String

        var id: String {
            "\(leaveOut ?? "-")>\(bring ?? "-")"
        }
    }

    var verdict: String
    var changes: [Change]
}

protocol CapsuleReviewing: Sendable {
    func review(_ details: TripDetails, closet: [Item]) async throws -> CapsuleReview
}

/// Asks Claude to look over the whole bag against the day plan: anything missing, redundant, or a weak day.
/// Items are labeled (P1… packed, C1… the rest of the closet) and the schema only allows those labels, so every
/// suggestion maps to a real item.
struct ClaudeCapsuleReviewer: CapsuleReviewing {
    static let maxChanges = 4
    static let none = "none"

    let client: ClaudeClient

    func review(_ details: TripDetails, closet: [Item]) async throws -> CapsuleReview {
        let labels = Labels(details: details, closet: closet)
        let json = try await client.structuredOutput(
            model: ClaudeStylist.model,
            effort: ClaudeStylist.effort,
            system: Self.systemPrompt,
            content: [.text(Self.brief(details, labels: labels))],
            schema: Self.schema(labels: labels)
        )
        return try Self.decode(json, labels: labels)
    }

    /// Short labels for the packed items and the rest of the closet's wearable pieces.
    struct Labels {
        let packed: [(label: String, item: Item)]
        let others: [(label: String, item: Item)]

        init(details: TripDetails, closet: [Item]) {
            let packedIDs = Set(details.packedItemIDs)
            let sorted = closet.sorted { ($0.category.layerOrder, $0.id) < ($1.category.layerOrder, $1.id) }
            packed = sorted.filter { packedIDs.contains($0.id) }.enumerated().map { ("P\($0 + 1)", $1) }
            others = sorted.filter { !packedIDs.contains($0.id) && $0.category.isCore }
                .enumerated().map { ("C\($0 + 1)", $1) }
        }

        func label(for itemID: String) -> String? {
            (packed + others).first { $0.item.id == itemID }?.label
        }

        func itemID(for label: String) -> String? {
            (packed + others).first { $0.label == label }?.item.id
        }
    }

    static let systemPrompt = """
    You are a personal stylist checking a suitcase before a trip. The user wants to pack as little as possible \
    and still look good every day. You get the day plan with the outfit planned for each occasion, the packed \
    pieces, and the rest of their closet.

    Give a one or two sentence verdict on the bag. Then suggest up to \(maxChanges) changes, most valuable first, \
    only where they clearly help: a day with no outfit or a weak one, a piece that adds little, or a swap that \
    makes more outfits work together. A change leaves out a packed piece, brings a closet piece, or both (a swap). \
    Use "\(none)" for the side a change doesn't use. Explain each in one short, plain sentence. Suggest no \
    changes if the bag is already right.
    """

    static func brief(_ details: TripDetails, labels: Labels) -> String {
        let stops = details.stops.map { "\($0.place.name) (\($0.nights) night\($0.nights == 1 ? "" : "s"))" }
        var lines = [
            "Trip: " + stops.joined(separator: ", ") + ".",
            "Laundry: \(details.laundry.title.lowercased()). Luggage: \(details.luggage.title.lowercased()).",
            "",
            "Days:",
        ]
        for (index, day) in details.days.enumerated() {
            let weather = day.weather
            let place = details.stop(forDay: index)?.place.name ?? ""
            lines.append(
                "Day \(index + 1), \(place): feels \(Int(weather.feelsLikeMinC.rounded()))–"
                    + "\(Int(weather.feelsLikeMaxC.rounded()))°C\(weather.dressFor.isRainy ? ", rain likely" : "")."
            )
            for planned in details.outfits where planned.dayIndex == index {
                let pieces = planned.itemIDs.compactMap(labels.label(for:))
                lines.append(
                    "  \(planned.occasion.title): " +
                        (pieces.isEmpty ? "nothing packed fits" : pieces.joined(separator: " + "))
                )
            }
        }
        lines.append("")
        lines.append("Packed:")
        lines += labels.packed.map { "\($0.label): \(ClaudeStylist.describe($0.item))" }
        lines.append("")
        lines.append("Rest of the closet:")
        lines += labels.others.map { "\($0.label): \(ClaudeStylist.describe($0.item))" }
        return lines.joined(separator: "\n")
    }

    static func schema(labels: Labels) -> JSONValue {
        let choice = { (options: [String]) in
            JSONValue.object([
                "type": .string("string"),
                "enum": .array(([none] + options).map(JSONValue.string)),
            ])
        }
        return .object([
            "type": .string("object"),
            "properties": .object([
                "verdict": .object(["type": .string("string")]),
                "changes": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "leave_out": choice(labels.packed.map(\.label)),
                            "bring": choice(labels.others.map(\.label)),
                            "why": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("leave_out"), .string("bring"), .string("why")]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
            ]),
            "required": .array([.string("verdict"), .string("changes")]),
            "additionalProperties": .bool(false),
        ])
    }

    static func decode(_ json: String, labels: Labels) throws -> CapsuleReview {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(ReviewResponse.self, from: Data(json.utf8)) else {
            throw ClaudeError.invalidResponse
        }
        let packedLabels = Set(labels.packed.map(\.label))
        var seen = Set<String>()
        let changes = response.changes.compactMap { change -> CapsuleReview.Change? in
            // Only packed items can be left out, and only closet items brought.
            let leaveOut = packedLabels.contains(change.leaveOut) ? labels.itemID(for: change.leaveOut) : nil
            let bring = packedLabels.contains(change.bring) ? nil : labels.itemID(for: change.bring)
            guard leaveOut != nil || bring != nil else { return nil }
            let result = CapsuleReview.Change(leaveOut: leaveOut, bring: bring, why: change.why)
            return seen.insert(result.id).inserted ? result : nil
        }
        return CapsuleReview(verdict: response.verdict, changes: Array(changes.prefix(maxChanges)))
    }
}

private struct ReviewResponse: Decodable {
    struct Change: Decodable {
        let leaveOut: String
        let bring: String
        let why: String
    }

    let verdict: String
    let changes: [Change]
}
