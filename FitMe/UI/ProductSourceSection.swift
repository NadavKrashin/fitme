import SwiftUI

/// Where an item's photo and tags came from, when it was matched to a product page online.
struct ProductSourceSection: View {
    let brand: String?
    let productURL: URL?

    var body: some View {
        if brand != nil || productURL != nil {
            Section("Found online") {
                if let brand {
                    LabeledContent("Brand", value: brand)
                }
                if let productURL {
                    Link(destination: productURL) {
                        Label("Product page", systemImage: "arrow.up.right")
                    }
                    .tint(Theme.terracotta)
                }
            }
            .editorialRow()
        }
    }
}

#if DEBUG
#Preview {
    Form { ProductSourceSection(brand: "J.Crew", productURL: URL(string: "https://example.com/p/tee")) }
}
#endif
