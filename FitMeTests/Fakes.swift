import CoreLocation
import FitEngine
import Foundation
@testable import FitMe

/// Records requests and answers with a canned status and body. Never touches the network.
actor RecordingTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let status: Int
    private let body: String

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

/// A Messages API success response whose text block is `text`, preceded by an (empty) thinking block.
func messagesResponse(text: String, stopReason: String = "end_turn") -> String {
    let escaped = String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
    return """
    {"id":"msg_test","type":"message","role":"assistant","model":"claude-opus-5-5",
     "content":[{"type":"thinking","thinking":"","signature":"sig"},{"type":"text","text":\(escaped)}],
     "stop_reason":"\(stopReason)","stop_details":null,
     "usage":{"input_tokens":1200,"output_tokens":90}}
    """
}

struct FakePhotoProcessor: PhotoProcessing {
    var fails = false

    func process(_ imageData: Data) async throws -> ProcessedPhoto {
        if fails {
            throw ImagePipelineError.unreadableImage
        }
        return ProcessedPhoto(
            photoJPEG: Data("photo".utf8) + imageData,
            cutoutPNG: Data("cutout".utf8) + imageData,
            taggingJPEG: imageData,
            colors: [ItemColor(hex: "#1F2A44")],
            hasCutout: true
        )
    }

    /// Marks the cutout so tests can tell the crop ran.
    func crop(_ photo: ProcessedPhoto, to _: ItemBox) async throws -> ProcessedPhoto {
        ProcessedPhoto(
            photoJPEG: photo.photoJPEG,
            cutoutPNG: Data("cropped".utf8) + photo.cutoutPNG,
            taggingJPEG: photo.taggingJPEG,
            colors: photo.colors,
            hasCutout: photo.hasCutout
        )
    }
}

struct FakeTagger: TaggingService {
    var error: Error?
    var itemBox: ItemBox?

    func tag(jpeg _: Data) async throws -> TaggedPhoto {
        if let error {
            throw error
        }
        var tags = ItemTags.blank
        tags.name = "Navy crewneck sweater"
        tags.subcategory = "sweater"
        tags.formality = 3
        tags.warmth = 3
        return TaggedPhoto(tags: tags, itemBox: itemBox)
    }
}

/// Photo-library loaders that hand back fixed bytes (nil = a photo that fails to load).
func loaders(_ images: [Data?]) -> [@Sendable () async -> Data?] {
    images.map { image in { image } }
}

struct FakeWeather: WeatherProviding {
    var result: Result<DayForecast, WeatherError> = .success(
        DayForecast(feelsLikeNowC: 8.6, feelsLikeMinC: 5, feelsLikeMaxC: 12, precipitationChance: 0.7)
    )

    func forecastHere() async throws -> DayForecast {
        try result.get()
    }
}

struct FakeLocator: Locating {
    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 32.08532, longitude: 34.78177)
    }
}

/// Picks the last candidate, so tests can tell it chose from what it was given.
struct FakeStylist: OutfitStylist {
    var error: Error?

    func pick(from candidates: [ScoredOutfit], context _: OutfitContext) async throws -> [StylistPick] {
        if let error {
            throw error
        }
        return candidates.suffix(1).map { StylistPick(outfit: $0, reason: "Works.") }
    }
}

@MainActor
func makeTodayModel(
    weather: FakeWeather = .init(),
    stylist: FakeStylist = .init(),
    anchor: Item? = nil
) -> TodayModel {
    TodayModel(generator: OutfitGenerator(), weatherService: weather, stylist: stylist, anchor: anchor)
}

/// Answers each request with the body for its host (status 500 for unknown hosts), and records requests.
actor RoutingTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let bodies: [String: String]

    init(_ bodies: [String: String]) {
        self.bodies = bodies
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let body = request.url?.host.flatMap { bodies[$0] }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: body == nil ? 500 : 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data((body ?? "{}").utf8), response)
    }
}

/// The same mild day everywhere, or a failure for the listed places.
struct FakeTripWeather: TripWeatherProviding {
    var failing: Set<String> = []
    var day = DailyWeather(feelsLikeMinC: 14, feelsLikeMaxC: 22, precipitationChance: 0.1, source: .forecast)

    func dailyWeather(at place: Place, days: [Date]) async throws -> [DailyWeather] {
        if failing.contains(place.name) {
            throw WeatherError.unavailable
        }
        return days.map { _ in day }
    }
}

/// Suggests leaving out the first packed item, so tests can apply it.
struct FakeCapsuleReviewer: CapsuleReviewing {
    var error: Error?

    func review(_ details: TripDetails, closet _: [Item]) async throws -> CapsuleReview {
        if let error {
            throw error
        }
        return CapsuleReview(
            verdict: "Solid.",
            changes: details.packedItemIDs.prefix(1)
                .map { CapsuleReview.Change(leaveOut: $0, bring: nil, why: "Spare.") }
        )
    }
}

enum TripFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let lisbon = Place(name: "Lisbon", detail: "Portugal", latitude: 38.72, longitude: -9.14)
    static let porto = Place(name: "Porto", detail: "Portugal", latitude: 41.15, longitude: -8.61)

    /// 6 November 2026, noon UTC.
    static let now = Date(timeIntervalSince1970: 1_793_966_400)

    static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    /// Lisbon for `nights` nights from tomorrow, laid out with mild weather on every day.
    static func trip(nights: Int = 4, stops: [Place] = [lisbon]) -> TripDetails {
        var details = TripDetails(
            startDate: day(1),
            stops: stops.map { TripStop(place: $0, nights: nights) }
        ).laidOut(calendar: calendar)
        for index in details.days.indices {
            details.days[index].weather = FakeTripWeather().day
        }
        return details
    }
}
