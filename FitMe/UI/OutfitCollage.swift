import FitEngine
import SwiftUI

/// A flat-lay of an outfit: the main pieces large on the left (top over bottom, or the one-piece), layers and shoes
/// smaller on the right.
struct OutfitCollage: View {
    let outfit: Outfit
    /// Cutout photo for an item id, when one exists.
    var image: (String) -> Data? = { _ in nil }
    var height: CGFloat = 240

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(spacing: -height * 0.05) {
                ForEach(mainPieces) { piece(for: $0, size: height / CGFloat(max(mainPieces.count, 1)) * 1.05) }
            }
            if !sidePieces.isEmpty {
                VStack(spacing: 0) {
                    ForEach(sidePieces) { piece(for: $0, size: height / 3.1) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .padding(.vertical, 12)
        .background(Theme.canvas, in: .rect(cornerRadius: 18, style: .continuous))
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

/// A suggested outfit: its flat-lay, what it is, and the actions that teach FitMe your taste.
struct OutfitCard: View {
    let outfit: ScoredOutfit
    var image: (String) -> Data? = { _ in nil }
    /// The stylist's one-line reason, when this card is one of its picks.
    var reason: String?
    var isSaved = false
    var isWorn = false
    var onToggleSave: () -> Void = {}
    var onDismiss: (() -> Void)?
    var onWear: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OutfitCollage(outfit: outfit.outfit, image: image)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.title(for: outfit.outfit))
                        .font(Theme.title(18))
                        .foregroundStyle(Theme.ink)
                    if let extras = Self.extras(for: outfit.outfit) {
                        Text(extras)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer(minLength: 0)
                Text("\(Int(outfit.score.rounded()))% match")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.butterInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.butter, in: .capsule)
                    .accessibilityLabel("Match \(Int(outfit.score.rounded())) out of 100")
            }

            if let reason {
                Label {
                    Text(reason).font(.callout).foregroundStyle(Theme.ink)
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(Theme.terracotta)
                }
            }

            HStack(spacing: 10) {
                CircleIconButton(
                    symbol: "heart",
                    label: isSaved ? "Unsave" : "Save",
                    isOn: isSaved,
                    action: onToggleSave
                )
                if let onDismiss {
                    CircleIconButton(symbol: "xmark", label: "Not for me", action: onDismiss)
                }
                Spacer()
                Button(action: onWear) {
                    Label(isWorn ? "Worn today" : "Wear this", systemImage: isWorn ? "checkmark" : "tshirt")
                }
                .buttonStyle(.pill(isWorn ? .quiet : .primary))
                .allowsHitTesting(!isWorn)
            }
        }
        .card()
    }

    /// "Navy crewneck sweater with beige chinos": the two pieces that define the outfit.
    static func title(for outfit: Outfit) -> String {
        let main = [outfit.top ?? outfit.onePiece, outfit.bottom].compactMap(\.self).map(\.name)
        guard let first = main.first else { return "Outfit" }
        return main.dropFirst().reduce(first) { "\($0) with \($1.lowercased())" }
    }

    /// The supporting pieces, if any: "Charcoal overcoat · Black chelsea boots".
    static func extras(for outfit: Outfit) -> String? {
        let extras = [outfit.outerwear, outfit.midLayer, outfit.shoes].compactMap(\.self).map(\.name)
        return extras.isEmpty ? nil : extras.joined(separator: " · ")
    }
}

#if DEBUG
#Preview {
    let items = PreviewData.items
    let outfit = Outfit(items: [items[0], items[2], items[4], items[6]])
    ScrollView {
        OutfitCard(
            outfit: ScoredOutfit(
                outfit: outfit,
                breakdown: OutfitScorer().score(outfit, context: OutfitContext(occasion: .casual))
            ),
            reason: "The denim jacket echoes the jeans and keeps it relaxed.",
            isSaved: true,
            onDismiss: {}
        )
        .padding()
    }
    .editorialCanvas()
    .environment(\.dependencies, .preview())
}
#endif
