#if DEBUG
import AVFoundation
import FitEngine
import Foundation
import SwiftData
import UIKit

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

    /// A draft waiting for review, and a product page it could be matched to.
    static let productDraft: CaptureDraft = {
        let draft = CaptureDraft(originalImage: Data())
        draft.status = .ready
        draft.tags = ItemTags(
            name: "Navy t-shirt",
            category: .top,
            subcategory: "t-shirt",
            pattern: .solid,
            formality: 2,
            warmth: 1,
            fit: .regular,
            isStatement: false,
            styleTags: [],
            waterResistant: false
        )
        container.mainContext.insert(draft)
        return draft
    }()

    static let productPage = ProductPage(snapshot: PageSnapshot(
        url: "https://example.com/p/broken-in-tee",
        title: "Broken-in tee",
        jsonLD: [],
        meta: ["og:title": "Broken-in tee", "og:image": "https://example.com/tee.jpg", "og:description": "Soft."],
        images: []
    ))

    static let captureModel = CaptureModel(
        processor: ImagePipeline(),
        tagger: PreviewTaggingService(),
        transport: URLSession.shared,
        context: container.mainContext
    )
}

/// Answers instantly with plausible tags, so previews never call the network.
struct PreviewTaggingService: TaggingService {
    func tag(jpeg _: Data, listing _: String?) async throws -> TaggedPhoto {
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

/// A camera with no viewfinder whose every shot is a plain grey square.
struct PreviewCamera: PhotoCapturing {
    var access: CameraAccess {
        .granted
    }

    var previewSession: AVCaptureSession? {
        nil
    }

    func requestAccess() async -> Bool {
        true
    }

    func start() async throws {}

    func stop() async {}

    func capturePhoto() async throws -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}

/// A calendar with dinner tonight.
struct PreviewCalendar: CalendarReading {
    var access: CalendarAccess {
        .granted
    }

    func requestAccess() async -> Bool {
        true
    }

    func events(from start: Date, to _: Date) async -> [CalendarEvent] {
        [CalendarEvent(title: "Dinner at Nopi", start: start.addingTimeInterval(4 * 3600), isAllDay: false)]
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

/// Previews act as if the user already allowed Claude.
struct PreviewConsent: AIConsentStoring {
    func read() -> AIConsent {
        .allowed
    }

    func write(_: AIConsent) {}
}
#endif
