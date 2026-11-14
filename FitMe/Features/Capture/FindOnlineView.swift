import SwiftData
import SwiftUI

/// Find an item's product page online: the owner says what they know, browses to the page, and picks a photo.
/// Used for new items in the Inbox and for items already in the closet.
struct FindOnlineView: View {
    private enum Step: Hashable {
        case browse(URL)
        case pick(ProductPage)
    }

    @Environment(\.dismiss) private var dismiss
    @Query private var records: [ItemRecord]
    /// Applies the chosen photo from the chosen page; the sheet closes once it succeeds.
    let apply: @MainActor (URL, ProductPage) async throws -> Void
    @State private var query: ProductQuery
    @State private var path: [Step] = []

    init(brand: String?, itemDescription: String, apply: @escaping @MainActor (URL, ProductPage) async throws -> Void) {
        self.apply = apply
        _query = State(initialValue: ProductQuery(brand: brand ?? "", itemDescription: itemDescription))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {} footer: {
                    Text(
                        "Tell FitMe what you know about this item and it searches the web. You open the product's "
                            + "page and pick its photo; nothing changes until you do."
                    )
                    .font(.subheadline)
                }
                Section {
                    TextField("Brand, e.g. J.Crew", text: $query.brand)
                        .autocorrectionDisabled()
                    if !knownBrands.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(knownBrands, id: \.self) { brand in
                                    ChipButton(title: brand, isOn: query.brand == brand) { query.brand = brand }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Brand")
                }

                Section {
                    TextField("What it is, e.g. navy t-shirt", text: $query.itemDescription)
                    TextField("Product name, if you know it", text: $query.productName)
                    TextField("Style number from the tag", text: $query.styleNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    TextField("Anything else, e.g. slim fit, 2024", text: $query.notes)
                } header: {
                    Text("The item")
                } footer: {
                    Text("The more you fill in, the closer the search lands. Only one field is needed.")
                }

                Section {
                    TextField("Paste a link", text: $query.link)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Already have the page?")
                } footer: {
                    Text("A link from the shop or an order email opens directly, without a search.")
                }
            }
            .editorialRow()
            .tint(Theme.terracotta)
            .editorialCanvas()
            .navigationTitle("Find it online")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { searchButton }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case let .browse(url):
                    ProductBrowserView(start: url) { path.append(.pick(query.applyingBrand(to: $0))) }
                case let .pick(page):
                    ProductPickView(page: page) { photo in
                        try await apply(photo, page)
                        dismiss()
                    }
                }
            }
        }
    }

    private var searchButton: some View {
        VStack(spacing: 8) {
            // Beside the button, not under the field: the keyboard covers the field's footer while typing.
            if query.hasUnusableLink {
                Text("That doesn't look like a web link. Copy the whole address from the shop's page.")
                    .font(.footnote)
                    .foregroundStyle(Theme.terracotta)
                    .multilineTextAlignment(.center)
            }
            Button {
                if let url = query.destination {
                    path.append(.browse(url))
                }
            } label: {
                Label(query.link.isEmpty ? "Search" : "Open page", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
            .disabled(query.destination == nil)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 12)
        .background(Theme.canvas)
    }

    /// Brands already in the closet, offered as one-tap choices.
    private var knownBrands: [String] {
        Set(records.compactMap(\.brand)).sorted()
    }
}

#if DEBUG
#Preview {
    FindOnlineView(brand: nil, itemDescription: "Navy t-shirt") { _, _ in }
        .modelContainer(PreviewData.container)
}
#endif
