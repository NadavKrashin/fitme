import Foundation
@testable import FitEngine

enum Fixtures {
    static let closet: [Item] = {
        let url = Bundle.module.url(forResource: "closet", withExtension: "json")!
        return try! JSONDecoder().decode([Item].self, from: Data(contentsOf: url))
    }()

    static let startDate = Date(timeIntervalSince1970: 1_790_000_000)

    static func item(_ id: String) -> Item {
        closet.first { $0.id == id }!
    }

    static func outfit(_ ids: String...) -> Outfit {
        Outfit(items: ids.map(item))
    }

    static func context(_ occasion: Occasion, _ weather: Weather = .mild) -> OutfitContext {
        OutfitContext(occasion: occasion, weather: weather, date: startDate)
    }

    static func days(_ count: Int, weather: Weather, occasions: [Occasion], from offset: Int = 0) -> [TripDay] {
        (0 ..< count).map {
            TripDay(
                date: startDate.addingTimeInterval(Double(offset + $0) * 86400),
                weather: weather,
                occasions: occasions
            )
        }
    }
}

func makeItem(
    _ id: String,
    _ category: ItemCategory,
    _ hexes: [String],
    pattern: ItemPattern = .solid,
    formality: Int = 2,
    warmth: Int = 1,
    fit: Fit = .regular,
    statement: Bool = false
) -> Item {
    let share = 1 / Double(hexes.count)
    return Item(
        id: id,
        name: id,
        category: category,
        colors: hexes.map { ItemColor(hex: $0, proportion: share) },
        pattern: pattern,
        formality: formality,
        warmth: warmth,
        fit: fit,
        isStatement: statement
    )
}

func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-3) -> Bool {
    abs(a - b) <= tolerance
}
