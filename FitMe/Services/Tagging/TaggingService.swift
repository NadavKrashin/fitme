import FitEngine
import Foundation

/// What a tagger can tell from a photo. Colors are measured from pixels instead (see `ImagePipeline`).
struct ItemTags: Codable, Hashable, Sendable {
    var name: String
    var category: ItemCategory
    var subcategory: String
    var pattern: ItemPattern
    var formality: Int
    var warmth: Int
    var fit: Fit
    var isStatement: Bool
    var styleTags: [StyleTag]
    var waterResistant: Bool

    /// Starting values when nothing could be tagged automatically.
    static let blank = ItemTags(
        name: "",
        category: .top,
        subcategory: "",
        pattern: .solid,
        formality: 2,
        warmth: 2,
        fit: .regular,
        isStatement: false,
        styleTags: [],
        waterResistant: false
    )

    func item(id: String, colors: [ItemColor]) -> Item {
        Item(
            id: id,
            name: name.isEmpty ? subcategory.capitalized : name,
            category: category,
            subcategory: subcategory.isEmpty ? nil : subcategory,
            colors: colors,
            pattern: pattern,
            formality: formality,
            warmth: warmth,
            fit: fit,
            isStatement: isStatement,
            styleTags: Set(styleTags),
            waterResistant: waterResistant
        )
    }
}

/// Where the item is in the tagging image, in thousandths of its width and height, origin top-left.
/// Used to crop away anything subject lift kept that isn't the item, like the face and legs of the person wearing it.
struct ItemBox: Codable, Hashable, Sendable {
    var x0: Int
    var y0: Int
    var x1: Int
    var y1: Int

    static let scale = 1000

    var isValid: Bool {
        [x0, y0, x1, y1].allSatisfy { (0 ... Self.scale).contains($0) } && x0 < x1 && y0 < y1
    }
}

struct TaggedPhoto: Sendable {
    let tags: ItemTags
    /// Nil when the model's box was unusable; the uncropped cutout is kept.
    let itemBox: ItemBox?
}

protocol TaggingService: Sendable {
    /// - Parameter jpeg: The item on a plain background, already downscaled.
    func tag(jpeg: Data) async throws -> TaggedPhoto
}

enum TaggingError: Error, Equatable {
    /// The model's JSON didn't decode, or a value was out of range.
    case invalidTags
}

/// Tags clothing photos with Claude, constrained to `ItemTags` by a JSON schema.
struct ClaudeTaggingService: TaggingService {
    /// One place to change the model. Opus 5.5 at low effort costs about a cent per photo.
    static let model = "claude-opus-5-5"
    static let effort = "low"

    let client: ClaudeClient

    func tag(jpeg: Data) async throws -> TaggedPhoto {
        let json = try await client.structuredOutput(
            model: Self.model,
            effort: Self.effort,
            system: Self.systemPrompt,
            content: [.jpeg(jpeg), .text("Tag this item.")],
            schema: Self.schema
        )
        return try Self.decode(json)
    }

    static func decode(_ json: String) throws -> TaggedPhoto {
        let data = Data(json.utf8)
        guard let tags = try? JSONDecoder().decode(ItemTags.self, from: data),
              (1 ... 5).contains(tags.formality),
              (1 ... 5).contains(tags.warmth)
        else { throw TaggingError.invalidTags }
        // A bad box only costs the crop, never the tags.
        let box = (try? JSONDecoder().decode(BoxField.self, from: data))?.itemBox
        return TaggedPhoto(tags: tags, itemBox: box?.isValid == true ? box : nil)
    }

    private struct BoxField: Decodable {
        let itemBox: ItemBox
    }

    static let systemPrompt = """
    You catalog clothing for a personal wardrobe app that builds outfits and packing lists. The photo shows one \
    item, usually with the background removed. It may be worn by a person; describe the clothing item only, never \
    the person.

    - name: short and specific, as the owner would say it ("Navy crewneck sweater", "Black chelsea boots").
    - category: top (tees, shirts, blouses, sweaters worn as the main top), midLayer (cardigans, blazers, \
    overshirts, fleeces worn over a top), outerwear (jackets and coats), bottom, onePiece (dresses, jumpsuits), \
    shoes, bag, accessory.
    - subcategory: one or two lowercase words ("t-shirt", "chinos", "loafers").
    - pattern: solid, textured (visible knit or weave, single color), stripe, check, floral, graphic (print, \
    logo, artwork), print (other repeating print), or other.
    - formality: 1 gym or lounge, 2 casual, 3 smart casual, 4 dressy or business, 5 black tie.
    - warmth: 1 very light (tank, shorts, sandals), 2 light (shirt, tee-weight knit, sneakers), 3 medium (sweater, \
    jeans, light jacket), 4 warm (heavy knit, boots, lined jacket), 5 very warm (wool coat, puffer).
    - fit: slim, regular, relaxed, or oversized, judged from the cut.
    - isStatement: true only if it draws the eye on its own (bold color, loud print, unusual shape).
    - styleTags: zero to three that clearly apply.
    - waterResistant: true only for rain jackets, shells, waxed or technical fabrics, rubber or leather boots.
    - itemBox: the tightest box around the item alone, as thousandths of the image width (x) and height (y) from \
    the top-left corner. Leave out the wearer's face, hair, skin and any other clothing.
    """

    /// Built from the engine's enums so the schema can never drift from the types it decodes into.
    static let schema: JSONValue = {
        func enumOf<T: RawRepresentable & CaseIterable>(_: T.Type) -> JSONValue where T.RawValue == String {
            .object(["type": .string("string"), "enum": .array(T.allCases.map { .string($0.rawValue) })])
        }
        let scale: JSONValue = .object(["type": .string("integer"), "enum": .array((1 ... 5).map(JSONValue.int))])
        let properties: [String: JSONValue] = [
            "name": .object(["type": .string("string")]),
            "category": enumOf(ItemCategory.self),
            "subcategory": .object(["type": .string("string")]),
            "pattern": enumOf(ItemPattern.self),
            "formality": scale,
            "warmth": scale,
            "fit": enumOf(Fit.self),
            "isStatement": .object(["type": .string("boolean")]),
            "styleTags": .object(["type": .string("array"), "items": enumOf(StyleTag.self)]),
            "waterResistant": .object(["type": .string("boolean")]),
            "itemBox": .object([
                "type": .string("object"),
                "properties": .object(Dictionary(uniqueKeysWithValues: ["x0", "y0", "x1", "y1"].map {
                    ($0, JSONValue.object(["type": .string("integer")]))
                })),
                "required": .array(["x0", "y0", "x1", "y1"].map(JSONValue.string)),
                "additionalProperties": .bool(false),
            ]),
        ]
        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(properties.keys.sorted().map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
    }()
}
