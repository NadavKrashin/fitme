#if DEBUG
import FitEngine
import Foundation
import SwiftData

/// A tiny closet for SwiftUI previews. Debug builds only; separate from the staging demo closet so previews stay
/// fast and stable.
@MainActor
enum PreviewData {
    static let items: [Item] = [
        Item(
            id: "p1",
            name: "White tee",
            category: .top,
            colors: [ItemColor(hex: "#F5F5F2")],
            formality: 1,
            warmth: 1
        ),
        Item(
            id: "p2",
            name: "Navy sweater",
            category: .top,
            colors: [ItemColor(hex: "#22304D")],
            formality: 3,
            warmth: 3
        ),
        Item(
            id: "p3",
            name: "Dark jeans",
            category: .bottom,
            colors: [ItemColor(hex: "#2C3E5C")],
            formality: 2,
            warmth: 3
        ),
        Item(
            id: "p4",
            name: "Beige chinos",
            category: .bottom,
            colors: [ItemColor(hex: "#C8B48F")],
            formality: 3,
            warmth: 2
        ),
        Item(
            id: "p5",
            name: "White sneakers",
            category: .shoes,
            colors: [ItemColor(hex: "#F4F4F2")],
            formality: 2,
            warmth: 2
        ),
        Item(
            id: "p6",
            name: "Brown loafers",
            category: .shoes,
            colors: [ItemColor(hex: "#6B4226")],
            formality: 4,
            warmth: 2
        ),
        Item(
            id: "p7",
            name: "Denim jacket",
            category: .outerwear,
            colors: [ItemColor(hex: "#4F6E92")],
            formality: 2,
            warmth: 2
        ),
    ]

    static let container: ModelContainer = {
        do {
            let container = try Persistence.makeInMemoryContainer()
            for item in items {
                container.mainContext.insert(ItemRecord(item: item))
            }
            return container
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }()

    static let captureModel = CaptureModel(
        processor: ImagePipeline(),
        tagger: PreviewTaggingService(),
        context: container.mainContext
    )
}

/// Answers instantly with plausible tags, so previews never call the network.
struct PreviewTaggingService: TaggingService {
    func tag(jpeg _: Data) async throws -> TaggedPhoto {
        var tags = ItemTags.blank
        tags.name = "Preview item"
        tags.subcategory = "t-shirt"
        return TaggedPhoto(tags: tags, itemBox: nil)
    }
}
#endif
