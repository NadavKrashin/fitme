import FitEngine
import SwiftUI

/// A color swatch standing in for an item's photo: its significant colors as bands, with a category glyph.
/// Real cutout photos replace this in Phase 1.
struct ItemThumbnail: View {
    let item: Item
    var size: CGFloat = 56

    var body: some View {
        let colors = item.significantColors
        HStack(spacing: 0) {
            ForEach(colors, id: \.hex) { color in
                color.swiftUIColor
            }
        }
        .overlay {
            Image(systemName: item.category.symbolName)
                .font(.system(size: size * 0.4))
                .foregroundStyle(colors.first?.contrastingColor ?? .primary)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.2))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.2)
                .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement()
        .accessibilityLabel(item.name)
    }
}

#if DEBUG
#Preview {
    HStack {
        ForEach(PreviewData.items.prefix(4)) { ItemThumbnail(item: $0) }
    }
    .padding()
}
#endif
