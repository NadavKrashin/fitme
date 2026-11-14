import Foundation

/// What the owner knows about an item, turned into the page the in-app browser opens to find it online.
struct ProductQuery: Equatable {
    var brand = ""
    var itemDescription = ""
    var productName = ""
    var styleNumber = ""
    var notes = ""
    /// A product page the owner already has, e.g. from an order email. Skips the search.
    var link = ""

    /// The closet is menswear only, so the search skips women's versions of the same product.
    private static let department = "men's"
    private static let searchEngine = "https://duckduckgo.com/"
    private static let searchHost = "duckduckgo.com"

    /// Search results have pictures too, but they are never the product page.
    static func isSearchPage(_ url: URL) -> Bool {
        guard let host = url.host() else { return false }
        return host == searchHost || host.hasSuffix(".\(searchHost)")
    }

    /// The pasted product page if there is one, otherwise a web search built from the other fields.
    /// Nil when there is nothing to go on.
    var destination: URL? {
        if !link.trimmed.isEmpty {
            return pastedURL
        }
        let terms = [brand, productName, itemDescription, styleNumber, notes].map(\.trimmed).filter { !$0.isEmpty }
        guard !terms.isEmpty, var components = URLComponents(string: Self.searchEngine) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: (terms + [Self.department]).joined(separator: " "))]
        return components.url
    }

    /// The brand the owner typed wins over whatever the page calls itself (often a parent company or a shop).
    func applyingBrand(to page: ProductPage) -> ProductPage {
        var page = page
        if !brand.trimmed.isEmpty {
            page.brand = brand.trimmed
        }
        return page
    }

    /// Accepts links pasted without a scheme ("jcrew.com/p/…").
    private var pastedURL: URL? {
        let text = link.trimmed
        let withScheme = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme, ["http", "https"].contains(scheme),
              let host = url.host(), host.contains(".")
        else { return nil }
        return url
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
