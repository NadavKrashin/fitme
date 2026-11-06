import FitEngine
import SwiftUI

/// One suggested outfit: its pieces outermost-first, with the engine's score.
struct OutfitRow: View {
    let outfit: ScoredOutfit
    /// Cutout photo for an item id, when one exists.
    var image: (String) -> Data? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(outfit.outfit.items) { ItemThumbnail(item: $0, image: image($0.id)) }
                Spacer(minLength: 0)
                Text(outfit.score, format: .number.precision(.fractionLength(0)))
                    .font(.headline.monospacedDigit())
                    .accessibilityLabel("Score \(Int(outfit.score.rounded())) out of 100")
            }
            Text(outfit.outfit.items.map(\.name).formatted(.list(type: .and)))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
