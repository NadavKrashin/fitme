import FitEngine
import Testing
@testable import FitMe

struct ClosetFilterTests {
    let navyChinos = Item(
        id: "b", name: "Navy chinos", category: .bottom, colors: [ItemColor(hex: "#27324A")], formality: 3, warmth: 2
    )
    let whiteTee = Item(
        id: "t", name: "White tee", category: .top, colors: [ItemColor(hex: "#F5F5F2")], formality: 1, warmth: 1
    )
    let greyBlazer = Item(
        id: "m", name: "Grey blazer", category: .midLayer, colors: [ItemColor(hex: "#9A9A9A")], formality: 4, warmth: 2
    )

    @Test func anEmptyFilterShowsEverything() {
        let filter = ClosetFilter()
        #expect([navyChinos, whiteTee, greyBlazer].allSatisfy { filter.matches($0, brand: nil) })
    }

    @Test func picksOfOneKindWidenAndKindsTogetherNarrow() {
        var filter = ClosetFilter(colors: [.navy, .white])
        #expect(filter.matches(navyChinos, brand: nil))
        #expect(filter.matches(whiteTee, brand: nil))
        #expect(!filter.matches(greyBlazer, brand: nil))

        filter.formality = [3, 4]
        #expect(filter.matches(navyChinos, brand: nil))
        #expect(!filter.matches(whiteTee, brand: nil), "white, but too casual")
    }

    @Test func brandFilterKeepsOnlyMatchedPieces() {
        let filter = ClosetFilter(brands: ["Uniqlo"])
        #expect(filter.matches(whiteTee, brand: "Uniqlo"))
        #expect(!filter.matches(navyChinos, brand: "J.Crew"))
        #expect(!filter.matches(greyBlazer, brand: nil), "pieces with no brand don't match a brand filter")
    }

    @Test func searchFindsNamesAndBrands() {
        let filter = ClosetFilter(search: "uniq")
        #expect(filter.matches(whiteTee, brand: "Uniqlo"))
        #expect(!filter.matches(navyChinos, brand: nil))
        #expect(ClosetFilter(search: "chinos").matches(navyChinos, brand: nil))
    }

    @Test func optionsListOnlyWhatTheClosetHas() {
        let options = ClosetFilter.Options([(navyChinos, "J.Crew"), (whiteTee, "Uniqlo"), (greyBlazer, nil)])
        #expect(options.colors == [.grey, .white, .navy])
        #expect(options.formality == [1, 3, 4])
        #expect(options.brands == ["J.Crew", "Uniqlo"])
        #expect(ClosetFilter(colors: [.navy], brands: ["Uniqlo"]).refinementCount == 2)
    }
}
