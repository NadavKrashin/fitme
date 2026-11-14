import FitEngine
import SwiftData
import SwiftUI

/// Outfits the user saved with ♥, and the history of what they wore, newest first.
struct SavedView: View {
    private enum Tab: String, CaseIterable {
        case saved = "Saved"
        case worn = "Worn"
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedOutfit.savedAt, order: .reverse) private var saved: [SavedOutfit]
    @Query(sort: \WearEntry.wornOn, order: .reverse) private var wears: [WearEntry]
    @Query private var records: [ItemRecord]
    @State private var tab = Tab.saved
    @State private var toast: Toast?
    @State private var selection: OutfitSelection?

    var body: some View {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.itemID, $0) })

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Picker("Show", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case .saved: savedList(recordsByID: recordsByID)
                    case .worn: wornList(recordsByID: recordsByID)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 80)
                .animation(.spring(duration: 0.4), value: saved.map(\.outfitID))
                .animation(.spring(duration: 0.4), value: wears.map(\.wornOn))
            }
            .navigationTitle("Saved")
            .editorialCanvas()
            .toast(toast) { toast = nil }
            .sheet(item: $selection) { OutfitDetailView(outfit: $0.outfit, occasion: $0.occasion) }
        }
    }

    // MARK: Saved

    @ViewBuilder
    private func savedList(recordsByID: [String: ItemRecord]) -> some View {
        if saved.isEmpty {
            emptyCard(
                symbol: "heart",
                title: "Your favorite outfits live here",
                message: "Tap ♥ on any suggestion in Today to keep it."
            )
        }
        ForEach(saved) { entry in
            if let outfit = outfit(entry.itemIDs, recordsByID: recordsByID) {
                savedCard(entry, outfit: outfit, image: { recordsByID[$0]?.cutout })
            }
        }
    }

    private func savedCard(_ entry: SavedOutfit, outfit: Outfit, image: @escaping (String) -> Data?) -> some View {
        let recorder = FeedbackRecorder(context: modelContext)
        let scored = ScoredOutfit(
            outfit: outfit,
            breakdown: OutfitScorer().score(outfit, context: OutfitContext(occasion: entry.occasion ?? .casual))
        )
        let wornToday = wears.first { $0.outfitID == entry.outfitID && Calendar.current.isDateInToday($0.wornOn) }
        return VStack(alignment: .leading, spacing: 8) {
            if let occasion = entry.occasion {
                Badge(text: occasion.title, tint: Theme.tint(for: occasion))
            }
            OutfitCard(
                outfit: scored,
                image: image,
                isSaved: true,
                isWorn: wornToday != nil,
                onToggleSave: {
                    recorder.removeSavedOutfit(id: entry.outfitID)
                    recorder.revert(.liked, for: outfit)
                    toast = Toast(symbol: "heart.slash", message: "Removed from saved")
                },
                onWear: {
                    if let wornToday {
                        unwear(wornToday)
                    } else {
                        let logged = recorder.wear(outfit, occasion: entry.occasion)
                        toast = Toast(symbol: "checkmark.circle.fill", message: "Logged as today's outfit") {
                            recorder.unwear(logged)
                        }
                    }
                },
                onOpen: { selection = OutfitSelection(outfit: outfit, occasion: entry.occasion) }
            )
        }
    }

    // MARK: Worn

    @ViewBuilder
    private func wornList(recordsByID: [String: ItemRecord]) -> some View {
        if wears.isEmpty {
            emptyCard(
                symbol: "tshirt",
                title: "What you wore, day by day",
                message: "Tap Wear this on a suggestion and it shows up here. Tap it again to take it back."
            )
        }
        let days = Dictionary(grouping: wears) { Calendar.current.startOfDay(for: $0.wornOn) }
        ForEach(days.keys.sorted(by: >), id: \.self) { day in
            VStack(alignment: .leading, spacing: 12) {
                Text(Self.dayTitle(day))
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.ink)
                ForEach(days[day] ?? []) { entry in
                    if let outfit = outfit(entry.itemIDs, recordsByID: recordsByID) {
                        WornOutfitRow(
                            entry: entry,
                            outfit: outfit,
                            image: { recordsByID[$0]?.cutout },
                            onOpen: { selection = OutfitSelection(outfit: outfit, occasion: entry.occasion) },
                            onRemove: { unwear(entry) }
                        )
                    }
                }
            }
            .card()
        }
    }

    private func unwear(_ entry: WearEntry) {
        FeedbackRecorder(context: modelContext).unwear(entry)
        toast = Toast(symbol: "arrow.uturn.backward", message: "Removed from what you wore")
    }

    private static func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(day) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    // MARK: Shared

    private func emptyCard(symbol: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(Theme.terracotta)
            Text(title)
                .font(Theme.title(20))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
        }
        .card(padding: 22)
    }

    /// The outfit as it is in the closet now; nil once too many of its pieces have been deleted.
    private func outfit(_ itemIDs: [String], recordsByID: [String: ItemRecord]) -> Outfit? {
        let items = itemIDs.compactMap { recordsByID[$0]?.item }
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
