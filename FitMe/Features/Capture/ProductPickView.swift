import SwiftUI

/// Confirm a product page as the item and choose which of its photos to use.
struct ProductPickView: View {
    @Environment(CaptureModel.self) private var capture
    let page: ProductPage
    let draft: CaptureDraft
    let onApplied: () -> Void
    @State private var selected: URL?
    @State private var isApplying = false
    @State private var errorMessage: String?

    private static let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(page.name).font(Theme.title())
                    ForEach(facts, id: \.self) { fact in
                        Text(fact).font(.subheadline).foregroundStyle(Theme.inkMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                SectionTitle(text: "Pick the photo that shows it best")
                LazyVGrid(columns: Self.columns, spacing: 12) {
                    ForEach(page.imageURLs, id: \.self) { url in
                        PhotoChoice(url: url, isSelected: url == selection) { selected = url }
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .editorialCanvas()
        .navigationTitle("Is this it?")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { controls }
    }

    private var selection: URL? {
        selected ?? page.imageURLs.first
    }

    private var facts: [String] {
        [page.brand, page.color, page.material].compactMap(\.self)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Text(errorMessage ?? "FitMe cuts the item out of this photo and asks Claude to tag it again.")
                .font(.footnote)
                .foregroundStyle(errorMessage == nil ? Theme.inkMuted : Theme.terracotta)
                .multilineTextAlignment(.center)
            Button {
                Task { await apply() }
            } label: {
                HStack {
                    if isApplying {
                        ProgressView().tint(Theme.canvas)
                    }
                    Text(isApplying ? "Fetching the photo…" : "Use this photo")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
            .disabled(isApplying || selection == nil)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 12)
        .background(Theme.canvas)
    }

    private func apply() async {
        guard let selection else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            try await capture.useProductPhoto(at: selection, from: page, for: draft)
            onApplied()
        } catch let error as ProductImportError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = ProductImportError.downloadFailed.userMessage
        }
    }
}

private struct PhotoChoice: View {
    let url: URL
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image): image.resizable().scaledToFit()
                case .failure: Image(systemName: "photo").foregroundStyle(Theme.inkMuted)
                default: ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.terracotta : Theme.line, lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.terracotta)
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Product photo")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        if let page = PreviewData.productPage {
            ProductPickView(page: page, draft: PreviewData.productDraft) {}
        }
    }
    .environment(PreviewData.captureModel)
    .modelContainer(PreviewData.container)
}
#endif
