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

/// Mild and dry, instantly.
struct PreviewWeatherService: WeatherProviding {
    func forecastHere() async throws -> DayForecast {
        DayForecast(feelsLikeNowC: 17, feelsLikeMinC: 12, feelsLikeMaxC: 21, precipitationChance: 0.2)
    }
}

/// Picks the first candidate with a canned reason.
struct PreviewStylist: OutfitStylist {
    func pick(from candidates: [ScoredOutfit], context _: OutfitContext) async throws -> [StylistPick] {
        candidates.prefix(1).map { StylistPick(outfit: $0, reason: "Calm neutrals with one warm accent.") }
    }
}

struct PreviewTripWeather: PlaceSearching, TripWeatherProviding {
    func places(matching query: String) async throws -> [Place] {
        [
            Place(name: "Lisbon", detail: "Portugal", latitude: 38.72, longitude: -9.14),
            Place(name: "Porto", detail: "Portugal", latitude: 41.15, longitude: -8.61),
        ].filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    func dailyWeather(at _: Place, days: [Date]) async throws -> [DailyWeather] {
        days.indices.map { index in
            DailyWeather(
                feelsLikeMinC: 12 + Double(index % 3),
                feelsLikeMaxC: 20 + Double(index % 3),
                precipitationChance: index == 2 ? 0.6 : 0.1,
                source: .forecast
            )
        }
    }
}

struct PreviewCapsuleReviewer: CapsuleReviewing {
    func review(_ details: TripDetails, closet _: [Item]) async throws -> CapsuleReview {
        CapsuleReview(
            verdict: "A tight, neutral bag: every top works with both bottoms.",
            changes: details.packedItemIDs.prefix(1).map {
                CapsuleReview.Change(leaveOut: $0, bring: nil, why: "It only makes one outfit.")
            }
        )
    }
}
#endif
