import SwiftUI

/// Explains matching an item to its product page online, and once matched, says where its photo came from.
/// Shown on the Inbox review screen and on a closet item.
struct ProductMatchCard: View {
    let brand: String?
    let productURL: URL?
    /// Opens Find online, to match the item or to change the match.
    let findOnline: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: productURL == nil ? "sparkle.magnifyingglass" : "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Theme.terracotta)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.title(18)).foregroundStyle(Theme.ink).lineLimit(2)
                Text(detail).font(.subheadline).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                actions.padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
    }

    private var title: String {
        guard productURL != nil else { return "Use the shop's photo" }
        return brand.map { "Matched to \($0)" } ?? "Matched online"
    }

    private var detail: String {
        productURL == nil
            ? "Find this item on the brand's website to get a clean photo and its exact details."
            : "The photo and details come from its product page."
    }

    @ViewBuilder
    private var actions: some View {
        // Styled buttons (not the default style) stay tappable on their own inside a list row.
        if let productURL {
            HStack {
                Link(destination: productURL) {
                    Label("View page", systemImage: "arrow.up.right")
                }
                .buttonStyle(.pill(.quiet))
                Button("Change", action: findOnline)
                    .buttonStyle(.pill(.quiet))
            }
        } else {
            Button(action: findOnline) {
                Label("Find it online", systemImage: "magnifyingglass")
            }
            .buttonStyle(.pill(.accent))
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        ProductMatchCard(brand: nil, productURL: nil) {}
        ProductMatchCard(brand: "J.Crew", productURL: URL(string: "https://example.com/p/tee")) {}
    }
    .padding()
    .editorialCanvas()
}
#endif
