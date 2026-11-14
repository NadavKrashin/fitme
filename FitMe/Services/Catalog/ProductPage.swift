import Foundation

/// What the in-app browser reads from the page on screen. Parsing happens in Swift so it can be tested.
struct PageSnapshot: Decodable, Equatable {
    struct Image: Decodable, Equatable {
        let src: String
        let width: Int
        let height: Int
    }

    let url: String
    let title: String
    /// The raw text of each `application/ld+json` script.
    let jsonLD: [String]
    /// Open Graph tags, keyed by property (`og:image`, `og:title`, `og:description`).
    let meta: [String: String]
    let images: [Image]

    /// Smaller images are icons, swatches and thumbnails, never the product photo.
    static let minimumImageSide = 300

    /// Runs in the page and returns a `PageSnapshot` as a JSON string.
    static let script = """
    (() => {
      const meta = {};
      for (const tag of document.querySelectorAll('meta[property^="og:"]')) {
        meta[tag.getAttribute('property')] = tag.content || '';
      }
      return JSON.stringify({
        url: location.href,
        title: document.title,
        jsonLD: [...document.querySelectorAll('script[type="application/ld+json"]')].map(s => s.textContent || ''),
        meta: meta,
        images: [...document.images]
          .filter(i => i.naturalWidth >= \(minimumImageSide) && i.naturalHeight >= \(minimumImageSide))
          .map(i => ({ src: i.currentSrc || i.src, width: i.naturalWidth, height: i.naturalHeight }))
      });
    })()
    """
}

/// A product as its shop describes it: the better photo and the stated facts for one closet item.
struct ProductPage: Hashable, Sendable {
    let url: URL
    var name: String
    var brand: String?
    var color: String?
    var material: String?
    var details: String?
    /// Best guesses first: the shop's own product photos, then the share image, then large images on the page.
    var imageURLs: [URL]

    private static let maxImages = 12
    private static let maxDetailsLength = 600

    /// Nil when the page has no usable photo, e.g. a search results page.
    init?(snapshot: PageSnapshot) {
        guard let pageURL = URL(string: snapshot.url) else { return nil }
        let product = Self.product(in: snapshot.jsonLD)

        let stated = Self.imageStrings(product?["image"])
            + Self.variants(of: product).flatMap { Self.imageStrings($0["image"]) }
        let onPage = snapshot.images
            .sorted { $0.width * $0.height > $1.width * $1.height }
            .map(\.src)
        var seen: Set<URL> = []
        let images = (stated + [snapshot.meta["og:image"]].compactMap(\.self) + onPage)
            .compactMap { URL(string: $0, relativeTo: pageURL)?.absoluteURL }
            .filter { ["http", "https"].contains($0.scheme ?? "") && seen.insert($0).inserted }
        guard !images.isEmpty else { return nil }

        url = pageURL
        name = Self.text(product?["name"]) ?? Self.text(snapshot.meta["og:title"]) ?? snapshot.title
        brand = Self.text(product?["brand"])
        color = Self.text(product?["color"])
        material = Self.text(product?["material"])
        details = (Self.text(product?["description"]) ?? Self.text(snapshot.meta["og:description"]))
            .map { String($0.prefix(Self.maxDetailsLength)) }
        imageURLs = Array(images.prefix(Self.maxImages))
    }

    /// The brand, or the shop's address when the page doesn't name one.
    var sourceName: String {
        brand ?? url.host() ?? "the shop"
    }

    /// The stated facts as plain lines, for the tagger.
    var listingText: String {
        [("Product", name), ("Brand", brand), ("Color", color), ("Material", material), ("Description", details)]
            .compactMap { label, value in value.map { "\(label): \($0)" } }
            .joined(separator: "\n")
    }

    // MARK: schema.org

    /// The first schema.org `Product` (or `ProductGroup`) in the page's structured data, however it is nested.
    private static func product(in scripts: [String]) -> [String: Any]? {
        scripts
            .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
            .flatMap(nodes)
            .first { node in types(of: node).contains { $0 == "Product" || $0 == "ProductGroup" } }
    }

    private static func nodes(in value: Any) -> [[String: Any]] {
        if let list = value as? [Any] {
            return list.flatMap(nodes)
        }
        guard let node = value as? [String: Any] else { return [] }
        return [node] + (node["@graph"].map(nodes) ?? [])
    }

    private static func types(of node: [String: Any]) -> [String] {
        (node["@type"] as? [String]) ?? (node["@type"] as? String).map { [$0] } ?? []
    }

    private static func variants(of product: [String: Any]?) -> [[String: Any]] {
        (product?["hasVariant"] as? [[String: Any]]) ?? []
    }

    /// schema.org allows a string, an object with a name, or a list of either.
    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let node as [String: Any]:
            return text(node["name"])
        case let list as [Any]:
            return list.lazy.compactMap(text).first
        default:
            return nil
        }
    }

    private static func imageStrings(_ value: Any?) -> [String] {
        switch value {
        case let string as String:
            [string]
        case let node as [String: Any]:
            [node["url"], node["contentUrl"]].compactMap { $0 as? String }.prefix(1).map(\.self)
        case let list as [Any]:
            list.flatMap(imageStrings)
        default:
            []
        }
    }
}
