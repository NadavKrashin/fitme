import os
import SwiftUI
import WebKit

/// The web view behind `ProductBrowserView`, and the reading of whatever product page is on screen.
@MainActor
final class ProductBrowser {
    let webView = WKWebView()

    init() {
        webView.allowsBackForwardNavigationGestures = true
    }

    /// Loads `url` unless a page is already open, so coming back to the browser keeps the owner's place.
    func open(_ url: URL) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        webView.goBack()
    }

    /// The product on the page being viewed, or nil if the page doesn't show one.
    func productOnScreen() async -> ProductPage? {
        guard let url = webView.url, !ProductQuery.isSearchPage(url) else { return nil }
        do {
            guard let json = try await webView.evaluateJavaScript(PageSnapshot.script) as? String else { return nil }
            return try ProductPage(snapshot: JSONDecoder().decode(PageSnapshot.self, from: Data(json.utf8)))
        } catch {
            Logger.capture.notice("Couldn't read the product page: \(String(describing: error))")
            return nil
        }
    }
}

/// A browser for finding an item's product page. The owner browses to the page and confirms it; nothing is read
/// from a page they haven't chosen.
struct ProductBrowserView: View {
    let start: URL
    let onProduct: (ProductPage) -> Void
    @State private var browser = ProductBrowser()
    @State private var isLoading = false
    @State private var isReading = false
    @State private var foundNothing = false

    var body: some View {
        WebView(webView: browser.webView)
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle("Find the product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isLoading {
                    ToolbarItem(placement: .primaryAction) { ProgressView() }
                }
            }
            .onAppear { browser.open(start) }
            .onReceive(browser.webView.publisher(for: \.isLoading)) { isLoading = $0 }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Text(
                foundNothing
                    ? "That isn't a product page yet. Open the product's own page, then try again."
                    : "Open the page that shows your item, then tap Use this page."
            )
            .font(.footnote)
            .foregroundStyle(foundNothing ? Theme.terracotta : Theme.inkMuted)
            .multilineTextAlignment(.center)

            HStack {
                CircleIconButton(symbol: "chevron.backward", label: "Previous page", action: browser.goBack)
                Button {
                    Task { await useThisPage() }
                } label: {
                    Label("Use this page", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill(.primary))
                .disabled(isReading)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 12)
        .background(Theme.canvas)
    }

    private func useThisPage() async {
        isReading = true
        defer { isReading = false }
        if let product = await browser.productOnScreen() {
            foundNothing = false
            onProduct(product)
        } else {
            foundNothing = true
        }
    }
}

private struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context _: Context) -> WKWebView {
        webView
    }

    func updateUIView(_: WKWebView, context _: Context) {}
}

#if DEBUG
#Preview {
    // An example domain reserved for documentation; statically valid, cannot fail.
    NavigationStack { ProductBrowserView(start: URL(string: "https://example.com")!) { _ in } }
}
#endif
