import FitEngine
import SwiftUI

/// An item's cutout photo, or a swatch of its colors with a category glyph when there's no photo yet.
struct ItemThumbnail: View {
    @Environment(\.dependencies) private var dependencies
    let item: Item
    var image: Data?
    var size: CGFloat = 56
    /// Collages lay cutouts directly on the card, without a tile behind each one.
    var isFramed = true

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: isFramed ? size * 0.2 : 0))
            .overlay {
                if isFramed {
                    RoundedRectangle(cornerRadius: size * 0.2)
                        .strokeBorder(Theme.line, lineWidth: 1)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(item.name)
    }

    @ViewBuilder
    private var content: some View {
        if let image, let uiImage = dependencies.thumbnails.image(for: item.id, data: image) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .background(isFramed ? Theme.card : .clear)
        } else {
            swatch
        }
    }

    private var swatch: some View {
        let colors = item.significantColors
        return HStack(spacing: 0) {
            ForEach(colors, id: \.hex) { $0.swiftUIColor }
        }
        .overlay {
            Image(systemName: item.category.symbolName)
                .font(.system(size: size * 0.4))
                .foregroundStyle(colors.first?.contrastingColor ?? Theme.ink)
        }
    }
}

#if DEBUG
#Preview {
    HStack {
        ForEach(PreviewData.items.prefix(4)) { ItemThumbnail(item: $0) }
    }
    .padding()
    .environment(\.dependencies, .preview())
}
#endif
