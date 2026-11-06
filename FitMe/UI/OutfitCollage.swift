import FitEngine
import SwiftUI

/// A flat-lay of an outfit: the main pieces large on the left (top over bottom, or the one-piece), layers and shoes
/// smaller on the right.
struct OutfitCollage: View {
    let outfit: Outfit
    /// Cutout photo for an item id, when one exists.
    var image: (String) -> Data? = { _ in nil }
    var height: CGFloat = 200

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(spacing: -height * 0.04) {
                ForEach(mainPieces) { piece(for: $0, size: height / CGFloat(max(mainPieces.count, 1))) }
            }
            VStack(spacing: 4) {
                ForEach(sidePieces) { piece(for: $0, size: height / 3.4) }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }

    private var mainPieces: [Item] {
        [outfit.top ?? outfit.onePiece, outfit.bottom].compactMap(\.self)
    }

    private var sidePieces: [Item] {
        [outfit.outerwear, outfit.midLayer, outfit.shoes].compactMap(\.self)
    }

    private func piece(for item: Item, size: CGFloat) -> some View {
        let photo = image(item.id)
        return ItemThumbnail(item: item, image: photo, size: size, isFramed: photo == nil)
    }
}

/// A suggested outfit with its collage, score, and the reactions that teach the engine your taste.
struct OutfitCard: View {
    let outfit: ScoredOutfit
    var image: (String) -> Data? = { _ in nil }
    /// The stylist's one-line reason, when this card is one of its picks.
    var reason: String?
    var reaction: OutfitFeedback?
    let onReact: (OutfitFeedback) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                OutfitCollage(outfit: outfit.outfit, image: image)
                Spacer(minLength: 0)
                Text(outfit.score, format: .number.precision(.fractionLength(0)))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Score \(Int(outfit.score.rounded())) out of 100")
            }
            if let reason {
                Text(reason).font(.subheadline)
            }
            Text(outfit.outfit.items.map(\.name).formatted(.list(type: .and)))
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                reactionButton(.liked, symbol: "hand.thumbsup", label: "Like")
                reactionButton(.disliked, symbol: "hand.thumbsdown", label: "Not for me")
                Spacer()
                Button {
                    onReact(.wore)
                } label: {
                    Label(reaction == .wore ? "Worn today" : "Wear this", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(reaction == .wore)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    private func reactionButton(_ feedback: OutfitFeedback, symbol: String, label: String) -> some View {
        Button { onReact(feedback) } label: {
            Image(systemName: reaction == feedback ? "\(symbol).fill" : symbol)
                .font(.title3)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(reaction == feedback ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    let items = PreviewData.items
    let outfit = Outfit(items: [items[0], items[2], items[4], items[6]])
    List {
        OutfitCard(
            outfit: ScoredOutfit(
                outfit: outfit,
                breakdown: OutfitScorer().score(outfit, context: OutfitContext(occasion: .casual))
            ),
            reason: "The denim jacket echoes the jeans and keeps it relaxed.",
            onReact: { _ in }
        )
    }
    .environment(\.dependencies, .preview())
}
#endif
