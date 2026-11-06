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
