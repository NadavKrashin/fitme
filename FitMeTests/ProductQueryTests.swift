import Foundation
import Testing
@testable import FitMe

struct ProductQueryTests {
    private func searchTerms(_ query: ProductQuery) throws -> String {
        let url = try #require(query.destination)
        #expect(url.host() == "duckduckgo.com")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return try #require(items.first { $0.name == "q" }?.value)
    }

    @Test func searchesWithEverythingTheOwnerTyped() throws {
        let query = ProductQuery(
            brand: " J.Crew ",
            itemDescription: "navy t-shirt",
            productName: "Broken-in tee",
            styleNumber: "AG008",
            notes: "bought 2024"
        )
        #expect(try searchTerms(query) == "J.Crew Broken-in tee navy t-shirt AG008 bought 2024 men's")
    }

    @Test func aBrandAloneIsEnough() throws {
        #expect(try searchTerms(ProductQuery(brand: "Uniqlo")) == "Uniqlo men's")
    }

    @Test func nothingTypedMeansNothingToOpen() {
        #expect(ProductQuery().destination == nil)
        #expect(ProductQuery(brand: "  ").destination == nil)
    }

    @Test(arguments: [
        "https://www.jcrew.com/p/mens/AG008",
        "www.jcrew.com/p/mens/AG008",
        "  jcrew.com/p/mens/AG008\n",
    ])
    func aPastedLinkSkipsTheSearch(link: String) throws {
        let url = try #require(ProductQuery(brand: "J.Crew", link: link).destination)
        #expect(url.scheme == "https")
        #expect(url.host()?.hasSuffix("jcrew.com") == true)
        #expect(url.path() == "/p/mens/AG008")
    }

    @Test func theSearchPageItselfIsNeverAProductPage() throws {
        let search = try #require(ProductQuery(brand: "Uniqlo").destination)
        #expect(ProductQuery.isSearchPage(search))
        #expect(try ProductQuery.isSearchPage(#require(URL(string: "https://html.duckduckgo.com/html?q=x"))))
        #expect(try !ProductQuery.isSearchPage(#require(URL(string: "https://www.uniqlo.com/us/en/products/E455360"))))
        #expect(try !ProductQuery.isSearchPage(#require(URL(string: "https://notduckduckgo.com/"))))
    }

    @Test func theTypedBrandWinsOverThePagesOwn() throws {
        let page = try #require(ProductPage(snapshot: PageSnapshot(
            url: "https://shop.example.com/p/tee",
            title: "Tee",
            jsonLD: [#"{"@type":"Product","name":"Tee","brand":"Parent Co","image":"https://cdn.example.com/t.jpg"}"#],
            meta: [:],
            images: []
        )))
        #expect(ProductQuery(brand: " J.Crew ").applyingBrand(to: page).brand == "J.Crew")
        #expect(ProductQuery().applyingBrand(to: page).brand == "Parent Co")
    }

    @Test(arguments: ["not a link", "javascript:alert(1)", "file:///etc/hosts", "ftp://shop.example.com/x"])
    func anUnusableLinkOpensNothing(link: String) {
        #expect(ProductQuery(brand: "J.Crew", link: link).destination == nil)
    }
}
