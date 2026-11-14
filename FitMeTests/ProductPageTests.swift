import Foundation
import Testing
@testable import FitMe

struct ProductPageTests {
    private func snapshot(
        url: String = "https://shop.example.com/p/tee",
        title: String = "Page title",
        jsonLD: [String] = [],
        meta: [String: String] = [:],
        images: [PageSnapshot.Image] = []
    ) -> PageSnapshot {
        PageSnapshot(url: url, title: title, jsonLD: jsonLD, meta: meta, images: images)
    }

    @Test func readsAProductFromStructuredData() throws {
        let page = try #require(ProductPage(snapshot: snapshot(jsonLD: ["""
        {"@context":"https://schema.org","@type":"Product","name":" Broken-in tee ",
         "brand":{"@type":"Brand","name":"J.Crew"},"color":"Navy","material":"100% cotton",
         "description":"Garment-dyed for softness.",
         "image":["https://cdn.example.com/a.jpg","/images/b.jpg"]}
        """])))

        #expect(page.url.absoluteString == "https://shop.example.com/p/tee")
        #expect(page.name == "Broken-in tee")
        #expect(page.brand == "J.Crew")
        #expect(page.color == "Navy")
        #expect(page.material == "100% cotton")
        #expect(page.imageURLs.map(\.absoluteString) == [
            "https://cdn.example.com/a.jpg",
            "https://shop.example.com/images/b.jpg",
        ])
        #expect(page.listingText == """
        Product: Broken-in tee
        Brand: J.Crew
        Color: Navy
        Material: 100% cotton
        Description: Garment-dyed for softness.
        """)
    }

    @Test func findsAProductNestedInAGraphAmongOtherData() throws {
        let page = try #require(ProductPage(snapshot: snapshot(jsonLD: [
            "not json",
            #"{"@type":"BreadcrumbList","itemListElement":[]}"#,
            """
            {"@graph":[{"@type":"WebSite","name":"Shop"},
                       {"@type":["Product","Thing"],"name":"501 jeans","brand":"Levi's",
                        "image":{"@type":"ImageObject","url":"https://cdn.example.com/501.jpg"}}]}
            """,
        ])))
        #expect(page.name == "501 jeans")
        #expect(page.brand == "Levi's")
        #expect(page.imageURLs.map(\.absoluteString) == ["https://cdn.example.com/501.jpg"])
    }

    @Test func aProductGroupOffersEveryVariantPhotoOnce() throws {
        let page = try #require(ProductPage(snapshot: snapshot(jsonLD: ["""
        {"@type":"ProductGroup","name":"Merino sweater","image":"https://cdn.example.com/navy.jpg",
         "hasVariant":[{"@type":"Product","color":"Navy","image":"https://cdn.example.com/navy.jpg"},
                       {"@type":"Product","color":"Black","image":"https://cdn.example.com/black.jpg"}]}
        """])))
        #expect(page.imageURLs.map(\.lastPathComponent) == ["navy.jpg", "black.jpg"])
    }

    @Test func fallsBackToTheShareImageThenTheLargestImagesOnThePage() throws {
        let page = try #require(ProductPage(snapshot: snapshot(
            meta: [
                "og:image": "https://cdn.example.com/share.jpg",
                "og:title": "Linen shirt",
                "og:description": "Airy.",
            ],
            images: [
                .init(src: "https://cdn.example.com/small.jpg", width: 400, height: 400),
                .init(src: "https://cdn.example.com/big.jpg", width: 1200, height: 1600),
                .init(src: "data:image/png;base64,AAAA", width: 900, height: 900),
            ]
        )))
        #expect(page.name == "Linen shirt")
        #expect(page.brand == nil)
        #expect(page.details == "Airy.")
        #expect(page.imageURLs.map(\.lastPathComponent) == ["share.jpg", "big.jpg", "small.jpg"])
        #expect(page.listingText == "Product: Linen shirt\nDescription: Airy.")
    }

    @Test func aPageWithoutPhotosIsNotAProduct() {
        #expect(ProductPage(snapshot: snapshot(jsonLD: [#"{"@type":"Product","name":"Ghost"}"#])) == nil)
        #expect(ProductPage(snapshot: snapshot(title: "Search results")) == nil)
    }

    @Test func usesThePageTitleWhenNothingNamesTheProduct() throws {
        let page = try #require(ProductPage(snapshot: snapshot(
            title: "Oxford shirt | Shop",
            images: [.init(src: "/img/oxford.jpg", width: 800, height: 1000)]
        )))
        #expect(page.name == "Oxford shirt | Shop")
        #expect(page.imageURLs.map(\.absoluteString) == ["https://shop.example.com/img/oxford.jpg"])
    }

    @Test func decodesWhatTheBrowserScriptReturns() throws {
        let json = """
        {"url":"https://shop.example.com/p/tee","title":"Tee","jsonLD":["{}"],
         "meta":{"og:image":"https://cdn.example.com/a.jpg"},
         "images":[{"src":"https://cdn.example.com/a.jpg","width":800,"height":800}]}
        """
        let decoded = try JSONDecoder().decode(PageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.images == [.init(src: "https://cdn.example.com/a.jpg", width: 800, height: 800)])
        #expect(ProductPage(snapshot: decoded)?.imageURLs.count == 1)
    }
}
