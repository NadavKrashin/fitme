import FitEngine
import SwiftData
import SwiftUI

/// Every piece of an outfit, in the order you'd put them on, each opening its item.
struct OutfitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [ItemRecord]
    let outfit: Outfit
    var occasion: Occasion?

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
                        }
                    }
                    .card()
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

    @ViewBuilder
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
            if record != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)

        if let record {
            NavigationLink { ItemDetailView(record: record) } label: { row }
                .buttonStyle(.plain)
        } else {
            row
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

    var id: String {
        outfit.id
    }
}
