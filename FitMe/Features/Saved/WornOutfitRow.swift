import FitEngine
import SwiftUI

/// A logged wear: a small flat-lay, what it was, and a way to take it back.
struct WornOutfitRow: View {
    let entry: WearEntry
    let outfit: Outfit
    var image: (String) -> Data? = { _ in nil }
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onOpen) {
                OutfitCollage(outfit: outfit, image: image, height: 110)
                    .frame(width: 130)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show every piece")
            VStack(alignment: .leading, spacing: 6) {
                if let occasion = entry.occasion {
                    Badge(text: occasion.title, tint: Theme.tint(for: occasion))
                }
                Text(OutfitCard.title(for: outfit))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                Button("Didn't wear it", systemImage: "arrow.uturn.backward", action: onRemove)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.terracotta)
            }
            Spacer(minLength: 0)
        }
    }
}
