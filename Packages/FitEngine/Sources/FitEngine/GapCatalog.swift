import Foundation

/// Wardrobe staples the closet analyzer considers adding. Each is the plain version a tagged photo of it would
/// produce, so it competes with real pieces on the same terms.
public enum GapCatalog {
    public static let menswear: [Item] = [
        Staple(
            id: "white-sneakers", name: "White leather sneakers", category: .shoes, hex: "#F4F4F2",
            formality: 2, warmth: 2, tags: [.minimal]
        ),
        Staple(
            id: "brown-boots", name: "Brown suede chelsea boots", category: .shoes, hex: "#6B4A33",
            formality: 3, warmth: 3, tags: [.classic]
        ),
        Staple(
            id: "brown-loafers", name: "Brown leather loafers", category: .shoes, hex: "#4A2E1F",
            formality: 4, warmth: 2, tags: [.classic]
        ),
        Staple(
            id: "black-oxfords", name: "Black oxford shoes", category: .shoes, hex: "#101010",
            formality: 5, warmth: 2, tags: [.classic]
        ),
        Staple(
            id: "running-shoes", name: "Running shoes", category: .shoes, hex: "#8A8F96",
            formality: 1, warmth: 2, tags: [.sporty]
        ),
        Staple(
            id: "dark-jeans", name: "Dark indigo jeans", category: .bottom, hex: "#2C3E5C",
            formality: 2, warmth: 3, tags: []
        ),
        Staple(
            id: "navy-chinos", name: "Navy chinos", category: .bottom, hex: "#27324A",
            formality: 3, warmth: 2, tags: [.classic]
        ),
        Staple(
            id: "stone-chinos", name: "Stone chinos", category: .bottom, hex: "#C8B48F",
            formality: 3, warmth: 2, tags: [.classic]
        ),
        Staple(
            id: "grey-trousers", name: "Grey wool trousers", category: .bottom, hex: "#6E6E70",
            formality: 4, warmth: 3, tags: [.classic]
        ),
        Staple(
            id: "running-shorts", name: "Running shorts", category: .bottom, hex: "#1B1B1B",
            formality: 1, warmth: 1, tags: [.sporty]
        ),
        Staple(
            id: "white-tee", name: "White crew tee", category: .top, hex: "#F5F5F2",
            formality: 1, warmth: 1, tags: [.minimal]
        ),
        Staple(
            id: "white-oxford", name: "White oxford shirt", category: .top, hex: "#F7F7F5",
            formality: 3, warmth: 2, tags: [.classic]
        ),
        Staple(
            id: "blue-oxford", name: "Light blue oxford shirt", category: .top, hex: "#A9C4E0",
            formality: 3, warmth: 2, tags: [.classic]
        ),
        Staple(
            id: "navy-sweater", name: "Navy crewneck sweater", category: .top, hex: "#22304D",
            formality: 3, warmth: 3, tags: [.classic]
        ),
        Staple(
            id: "grey-sweater", name: "Grey merino sweater", category: .top, hex: "#8A8D91",
            formality: 3, warmth: 3, tags: [.classic]
        ),
        Staple(
            id: "training-tee", name: "Training tee", category: .top, hex: "#2B2B2B",
            formality: 1, warmth: 1, tags: [.sporty]
        ),
        Staple(
            id: "navy-blazer", name: "Navy blazer", category: .midLayer, hex: "#1F2B48",
            formality: 4, warmth: 2, tags: [.classic]
        ),
        Staple(
            id: "denim-jacket", name: "Denim jacket", category: .outerwear, hex: "#4F6E92",
            formality: 2, warmth: 2, tags: []
        ),
        Staple(
            id: "rain-jacket", name: "Navy rain jacket", category: .outerwear, hex: "#1F2B48",
            formality: 2, warmth: 2, tags: [.outdoor], waterResistant: true
        ),
        Staple(
            id: "camel-overcoat", name: "Camel overcoat", category: .outerwear, hex: "#C19A6B",
            formality: 4, warmth: 5, tags: [.classic]
        ),
    ].map(\.item)

    private struct Staple {
        let id: String
        let name: String
        let category: ItemCategory
        let hex: String
        let formality: Int
        let warmth: Int
        let tags: Set<StyleTag>
        var waterResistant = false

        var item: Item {
            Item(
                id: "gap-\(id)",
                name: name,
                category: category,
                colors: [ItemColor(hex: hex)],
                formality: formality,
                warmth: warmth,
                styleTags: tags,
                waterResistant: waterResistant
            )
        }
    }
}
