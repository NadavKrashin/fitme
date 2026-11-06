import FitEngine
import SwiftData
import SwiftUI

/// Outfits the user saved with ♥, newest first.
struct SavedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedOutfit.savedAt, order: .reverse) private var saved: [SavedOutfit]
    @Query private var records: [ItemRecord]
    @State private var toast: Toast?
    @State private var wornToday: Set<String> = []

    var body: some View {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.itemID, $0) })

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if saved.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "heart")
                                .font(.title)
                                .foregroundStyle(Theme.terracotta)
                            Text("Your favorite outfits live here")
                                .font(Theme.title(20))
                                .foregroundStyle(Theme.ink)
                            Text("Tap ♥ on any suggestion in Today to keep it.")
                                .font(.callout)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .card(padding: 22)
                    }
                    ForEach(saved) { entry in
                        if let outfit = outfit(for: entry, recordsByID: recordsByID) {
                            savedCard(entry, outfit: outfit, image: { recordsByID[$0]?.cutout })
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 80)
                .animation(.spring(duration: 0.4), value: saved.map(\.outfitID))
            }
            .navigationTitle("Saved")
            .editorialCanvas()
            .toast(toast) { toast = nil }
        }
    }

    private func savedCard(_ entry: SavedOutfit, outfit: Outfit, image: @escaping (String) -> Data?) -> some View {
        let recorder = FeedbackRecorder(context: modelContext)
        let scored = ScoredOutfit(
            outfit: outfit,
            breakdown: OutfitScorer().score(outfit, context: OutfitContext(occasion: entry.occasion ?? .casual))
        )
        return VStack(alignment: .leading, spacing: 8) {
            if let occasion = entry.occasion {
                Badge(text: occasion.title, tint: Theme.tint(for: occasion))
            }
            OutfitCard(
                outfit: scored,
                image: image,
                isSaved: true,
                isWorn: wornToday.contains(entry.outfitID),
                onToggleSave: {
                    recorder.removeSavedOutfit(id: entry.outfitID)
                    recorder.revert(.liked, for: outfit)
                    toast = Toast(symbol: "heart.slash", message: "Removed from saved")
                },
                onWear: {
                    wornToday.insert(entry.outfitID)
                    recorder.record(.wore, for: outfit)
                    toast = Toast(symbol: "checkmark.circle.fill", message: "Logged as today's outfit")
                }
            )
        }
    }

    /// The saved outfit as it is in the closet now; nil once too many of its pieces have been deleted.
    private func outfit(for entry: SavedOutfit, recordsByID: [String: ItemRecord]) -> Outfit? {
        let items = entry.itemIDs.compactMap { recordsByID[$0]?.item }
        return items.count >= 2 ? Outfit(items: items) : nil
    }
}

#if DEBUG
#Preview {
    SavedView()
        .environment(\.dependencies, .preview())
        .modelContainer(PreviewData.container)
}
#endif
