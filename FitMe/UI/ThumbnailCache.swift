import UIKit

/// Decoded item images, so scrolling a grid doesn't re-decode PNGs on every frame.
final class ThumbnailCache: @unchecked Sendable {
    /// NSCache is internally synchronized; it just isn't annotated Sendable.
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 300
    }

    /// `key` must change whenever `data` does (e.g. item id plus a version).
    func image(for key: String, data: Data) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}
