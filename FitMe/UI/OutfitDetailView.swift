import FitEngine
import SwiftData
import SwiftUI

/// Every piece of an outfit, in the order you'd put them on, each opening its item. When `swapping` is given (on
/// Today), each piece can be swapped for another from the closet.
struct OutfitDetailView: View {
    /// Where swap options come from and where a swap goes.
    struct Swapping {
        /// Versions of the outfit with this piece changed, best first.
        let options: (_ piece: Item, _ outfit: Outfit) -> [ScoredOutfit]
        /// Replaces `from` with the swapped version wherever the outfit came from.
        let apply: (_ from: Outfit, _ to: ScoredOutfit) -> Void
    }

    @Environment(\.dismiss) private var dismiss
    @Query private var records: [ItemRecord]
    var occasion: Occasion?
    var swapping: Swapping?
    @State private var outfit: Outfit
    /// The piece whose replacements are showing.
    @State private var swappingPiece: Item?

    init(outfit: Outfit, occasion: Occasion? = nil, swapping: Swapping? = nil) {
        _outfit = State(initialValue: outfit)
        self.occasion = occasion
        self.swapping = swapping
    }

    var body: some View {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.itemID, $0) })

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    OutfitCollage(outfit: outfit, image: { recordsByID[$0]?.cutout }, height: 280)
                    VStack(alignment: .leading, spacing: 8) {
                        if let occasion {
                            Badge(text: occasion.title, tint: Theme.tint(for: occasion))
                        }
                        Text(OutfitCard.title(for: outfit))
                            .font(Theme.title(22))
                            .foregroundStyle(Theme.ink)
                        Text(Self.howToWear(outfit))
                            .font(.callout)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Self.wearingOrder(outfit)) { item in
                            pieceRow(item, record: recordsByID[item.id])
                            if let swapping, swappingPiece == item {
                                swapOptions(for: item, swapping: swapping, recordsByID: recordsByID)
                            }
                        }
                    }
                    .card()
                    .animation(.spring(duration: 0.3), value: swappingPiece)
                }
                .padding(Theme.gutter)
            }
            .editorialCanvas()
            .navigationTitle("The outfit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func pieceRow(_ item: Item, record: ItemRecord?) -> some View {
        let row = HStack(spacing: 14) {
            ItemThumbnail(item: item, image: record?.cutout, size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.role(of: item).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                Text(item.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text(Self.details(of: item))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)

        // The swap button sits beside the link, not inside it, or the link would take its taps.
        return HStack(spacing: 8) {
            if let record {
                NavigationLink { ItemDetailView(record: record) } label: { row }
                    .buttonStyle(.plain)
            } else {
                row
            }
            if swapping != nil {
                let isOpen = swappingPiece == item
                Button(isOpen ? "Close" : "Swap") {
                    swappingPiece = isOpen ? nil : item
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.pill(.quiet))
                .accessibilityLabel(isOpen ? "Close swaps" : "Swap \(item.name)")
            }
        }
    }

    @ViewBuilder
    private func swapOptions(for piece: Item, swapping: Swapping, recordsByID: [String: ItemRecord]) -> some View {
        let options = swapping.options(piece, outfit)
        if options.isEmpty {
            Text("Nothing else in your closet works here today.")
                .font(.footnote)
                .foregroundStyle(Theme.inkMuted)
                .padding(.vertical, 8)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(options) { option in
                        let replacement = option.outfit.items.first { $0.category == piece.category }
                        Button {
                            swapping.apply(outfit, option)
                            outfit = option.outfit
                            swappingPiece = nil
                        } label: {
                            VStack(spacing: 6) {
                                if let replacement {
                                    ItemThumbnail(
                                        item: replacement,
                                        image: recordsByID[replacement.id]?.cutout,
                                        size: 84
                                    )
                                } else {
                                    Image(systemName: "minus.circle")
                                        .font(.title)
                                        .foregroundStyle(Theme.inkMuted)
                                        .frame(width: 84, height: 84)
                                        .background(Theme.photoTile, in: .rect(cornerRadius: 17))
                                }
                                Text(replacement?.name ?? "Without it")
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                Text("\(option.matchPercent)% match")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            .frame(width: 96)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    /// Base first, then layers from the inside out, then shoes.
    static func wearingOrder(_ outfit: Outfit) -> [Item] {
        [outfit.top ?? outfit.onePiece, outfit.bottom, outfit.midLayer, outfit.outerwear, outfit.shoes]
            .compactMap(\.self)
    }

    static func role(of item: Item) -> String {
        switch item.category {
        case .top: "Top"
        case .onePiece: "One-piece"
        case .bottom: "Bottoms"
        case .midLayer: "Layer over the top"
        case .outerwear: "Jacket or coat"
        case .shoes: "Shoes"
        case .bag: "Bag"
        case .accessory: "Accessory"
        }
    }

    /// "beige and white · Casual · Light · Relaxed fit"
    static func details(of item: Item) -> String {
        let colors = item.significantColors.map(\.name).joined(separator: " and ")
        return [
            colors,
            ScaleLabels.formality(item.formality),
            ScaleLabels.warmth(item.warmth),
            "\(item.fit.title) fit",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    /// How the layers go together, e.g. "Cardigan over the shirt, jacket on top."
    static func howToWear(_ outfit: Outfit) -> String {
        guard let base = outfit.top ?? outfit.onePiece else { return "" }
        let baseName = base.name.lowercased()
        switch (outfit.midLayer, outfit.outerwear) {
        case let (mid?, outer?):
            return "\(mid.name) over the \(baseName), \(outer.name.lowercased()) on top."
        case let (mid?, nil):
            return "\(mid.name) over the \(baseName)."
        case let (nil, outer?):
            return "\(outer.name) over the \(baseName)."
        case (nil, nil):
            return "No layers needed."
        }
    }
}

#if DEBUG
#Preview {
    let items = PreviewData.items
    OutfitDetailView(outfit: Outfit(items: [items[0], items[2], items[4], items[6]]), occasion: .casual)
        .environment(\.dependencies, .preview())
        .modelContainer(PreviewData.container)
}
#endif

/// An outfit opened for detail, as a sheet item.
struct OutfitSelection: Identifiable {
    let outfit: Outfit
    var occasion: Occasion?
    var swapping: OutfitDetailView.Swapping?

    var id: String {
        outfit.id
    }
}
