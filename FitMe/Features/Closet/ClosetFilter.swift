import FitEngine
import Foundation

/// What the closet grid shows: a category, a search, and any colors, dress codes and brands picked in Filters.
/// Within one kind, any pick matches ("navy or white"); across kinds, all must match ("navy, and dressy").
struct ClosetFilter: Equatable {
    var category: ItemCategory?
    var search = ""
    var colors: Set<ColorFamily> = []
    /// `Item.formality` levels, 1...5.
    var formality: Set<Int> = []
    var brands: Set<String> = []

    /// How many color, dress-code and brand picks are active (category and search show for themselves).
    var refinementCount: Int {
        colors.count + formality.count + brands.count
    }

    mutating func clearRefinements() {
        colors = []
        formality = []
        brands = []
    }

    func matches(_ item: Item, brand: String?) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return (category == nil || item.category == category)
            && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
                || brand?.localizedCaseInsensitiveContains(query) == true)
            && (colors.isEmpty || item.significantColors.contains { colors.contains($0.family) })
            && (formality.isEmpty || formality.contains(item.formality))
            && (brands.isEmpty || brand.map(brands.contains) == true)
    }

    /// The choices worth offering for a closet: only colors, dress codes and brands it actually has.
    struct Options: Equatable {
        let colors: [ColorFamily]
        let formality: [Int]
        let brands: [String]

        init(_ pieces: [(item: Item, brand: String?)]) {
            let families = Set(pieces.flatMap { $0.item.significantColors.map(\.family) })
            colors = ColorFamily.allCases.filter(families.contains)
            formality = Set(pieces.map(\.item.formality)).sorted()
            brands = Set(pieces.compactMap(\.brand)).sorted { $0.localizedCompare($1) == .orderedAscending }
        }
    }
}
