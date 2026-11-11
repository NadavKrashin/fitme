import FitEngine
import SwiftData
import SwiftUI

/// The closet as a whole: what to buy next, what's hard to style, the workhorses, what's resting, and learned taste.
/// Pushed from the Closet tab, whose navigation stack opens item details.
struct InsightsView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ItemRecord.name) private var records: [ItemRecord]
    @Query private var profiles: [StyleProfileRecord]
    @State private var model: InsightsModel?
    @State private var isConfirmingReset = false
    @State private var toast: Toast?

    /// How many resting pieces to list before summarizing the rest.
    private static let restingLimit = 8

    var body: some View {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.itemID, $0) })

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                switch model?.state {
                case let .analyzed(insights):
                    headline(insights)
                    gaps(insights, recordsByID: recordsByID)
                    hardToStyle(insights, recordsByID: recordsByID)
                    workhorses(insights, recordsByID: recordsByID)
                case .analyzing, .idle, nil:
                    HStack(spacing: 12) {
                        ProgressView().tint(Theme.terracotta)
                        Text("Trying every piece with everything else…")
                            .font(.callout)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .card()
                }
                resting
                taste
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 80)
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .editorialCanvas()
        .toast(toast) { toast = nil }
        .task(id: records.map(\.itemID)) {
            let model = model ?? dependencies.makeInsightsModel()
            self.model = model
            await model.analyze(records.map(\.item))
        }
        .confirmationDialog("Forget what FitMe learned?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                FeedbackRecorder(context: modelContext).resetLearning()
                toast = Toast(symbol: "arrow.counterclockwise", message: "FitMe starts fresh")
            }
        } message: {
            Text("Suggestions go back to the style rules alone. Saved outfits and wear history stay.")
        }
    }

    // MARK: Closet

    private func headline(_ insights: ClosetInsights) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(records.count) pieces, \(insights.totalLooks) looks")
                .font(Theme.display(30))
                .foregroundStyle(Theme.ink)
            Text("A look is a top and bottom (or a one-piece) with shoes that make a good outfit on some kind of day.")
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
        }
    }

    @ViewBuilder
    private func gaps(_ insights: ClosetInsights, recordsByID: [String: ItemRecord]) -> some View {
        SectionTitle(text: "Best next buy")
        if insights.gaps.isEmpty {
            Text("No staple would add an outfit you can't already put together. Nothing to buy.")
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
                .card()
        } else {
            ForEach(insights.gaps) { gap in
                GapCard(gap: gap, names: { recordsByID[$0]?.name.lowercased() })
            }
        }
    }

    @ViewBuilder
    private func hardToStyle(_ insights: ClosetInsights, recordsByID: [String: ItemRecord]) -> some View {
        SectionTitle(text: "Hard to style")
        let hard = insights.hardToStyle.compactMap { recordsByID[$0] }
        if hard.isEmpty {
            Text("Every piece makes at least \(ClosetAnalyzer.fewLooks) looks. Nothing is stranded.")
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
                .card()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("These clash with the rest of your closet on dress code or color.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.bottom, 6)
                ForEach(hard) { record in
                    ItemLinkRow(record: record, detail: Self.looksText(insights.looksByItem[record.itemID] ?? 0))
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private func workhorses(_ insights: ClosetInsights, recordsByID: [String: ItemRecord]) -> some View {
        let top = insights.workhorses().compactMap { recordsByID[$0] }
        if !top.isEmpty {
            SectionTitle(text: "Workhorses")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(top) { record in
                    ItemLinkRow(record: record, detail: Self.looksText(insights.looksByItem[record.itemID] ?? 0))
                }
            }
            .card()
        }
    }

    private static func looksText(_ count: Int) -> String {
        switch count {
        case 0: "No looks yet"
        case 1: "In 1 look"
        default: "In \(count) looks"
        }
    }

    // MARK: Wear

    @ViewBuilder
    private var resting: some View {
        let resting = InsightsModel.resting(records)
        if !resting.isEmpty {
            SectionTitle(text: "Resting in the closet")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(resting.prefix(Self.restingLimit)) { record in
                    ItemLinkRow(record: record, detail: Self.restingText(record))
                }
                if resting.count > Self.restingLimit {
                    Text("and \(resting.count - Self.restingLimit) more")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.top, 4)
                }
            }
            .card()
        }
    }

    private static func restingText(_ record: ItemRecord) -> String {
        guard let lastWorn = record.lastWorn else { return "Never worn" }
        return "Last worn \(lastWorn.formatted(.relative(presentation: .named)))"
    }

    // MARK: Taste

    @ViewBuilder
    private var taste: some View {
        let profile = profiles.first?.profile ?? StyleProfile()
        let pairings = profile.colorPairings()
        SectionTitle(text: "Your taste")
        VStack(alignment: .leading, spacing: 12) {
            if profile.isEmpty {
                Text("React to suggestions in Today and FitMe learns what you like: ♥ to save, ✕ to hide, "
                    + "and Wear this.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                Text("Learned from your reactions to \(profile.pairAffinity.count) pairings of pieces.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
                pairingList("You like", pairings.liked)
                pairingList("You skip", pairings.disliked)
                Button("Forget what FitMe learned") { isConfirmingReset = true }
                    .buttonStyle(.pill(.quiet))
            }
        }
        .card()
    }

    @ViewBuilder
    private func pairingList(_ title: String, _ pairings: [ColorPairing]) -> some View {
        if !pairings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                ForEach(pairings.prefix(3)) { pairing in
                    HStack(spacing: 10) {
                        HStack(spacing: -6) {
                            FamilySwatch(family: pairing.first)
                            FamilySwatch(family: pairing.second)
                        }
                        Text(pairing.first == pairing.second
                            ? "\(pairing.first.name.capitalized) on \(pairing.first.name)"
                            : "\(pairing.first.name.capitalized) with \(pairing.second.name)")
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A missing staple, what it would unlock, and which owned pieces it would help.
private struct GapCard: View {
    let gap: GapSuggestion
    /// Lowercased name for a closet item id.
    let names: (String) -> String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ItemThumbnail(item: gap.item, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(gap.item.name)
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.ink)
                Badge(text: "Unlocks \(gap.newOutfits) new outfits", tint: (Theme.butter, Theme.butterInk))
                if let partners = Self.list(gap.pairsWith.compactMap(names)) {
                    Text("Goes with your \(partners).")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkMuted)
                }
                if let rescued = Self.list(gap.rescues.compactMap(names)) {
                    Text("More ways to wear your \(rescued).")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.sageInk)
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    /// "a", "a and b", or "a, b and 3 more".
    private static func list(_ names: [String]) -> String? {
        switch names.count {
        case 0: nil
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }
}

/// An item with a one-line note, opening its detail screen.
private struct ItemLinkRow: View {
    let record: ItemRecord
    let detail: String

    var body: some View {
        NavigationLink(value: record.itemID) {
            HStack(spacing: 12) {
                ItemThumbnail(item: record.item, image: record.cutout, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name).foregroundStyle(Theme.ink)
                    Text(detail).font(.footnote).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct FamilySwatch: View {
    let family: ColorFamily

    var body: some View {
        Circle()
            .fill(family.swatch)
            .frame(width: 26, height: 26)
            .overlay { Circle().strokeBorder(Theme.line, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        InsightsView()
    }
    .environment(\.dependencies, .preview())
    .modelContainer(PreviewData.container)
}
#endif
