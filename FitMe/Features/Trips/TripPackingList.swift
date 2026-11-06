import FitEngine
import SwiftUI

/// What goes in the bag: the stylist's review, packed pieces by category, and counted essentials, each ticked off
/// while packing.
struct TripPackingList: View {
    @Bindable var model: TripModel
    let recordsByID: [String: ItemRecord]
    @State private var isAdding = false

    var body: some View {
        let closet = recordsByID.values.map(\.item)
        let packed = model.details.packedItemIDs.compactMap { recordsByID[$0]?.item }
        let essentials = Essentials.checklist(for: model.details)
        let keys = packed.map(\.id) + essentials.map(\.name)
        let done = keys.count(where: model.isChecked)

        VStack(alignment: .leading, spacing: 22) {
            CapsuleReviewCard(model: model, recordsByID: recordsByID)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(done) of \(keys.count) in the bag")
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.ink)
                ProgressView(value: Double(done), total: Double(max(keys.count, 1)))
                    .tint(Theme.sageInk)
            }

            ForEach(ItemCategory.allCases, id: \.self) { category in
                let items = packed.filter { $0.category == category }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .padding(.bottom, 4)
                        ForEach(items) { item in
                            itemRow(item, closet: closet)
                        }
                    }
                    .card()
                }
            }

            Button {
                isAdding = true
            } label: {
                Label("Add from closet", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.quiet))

            VStack(alignment: .leading, spacing: 4) {
                Text("ESSENTIALS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.bottom, 4)
                ForEach(essentials, id: \.name) { essential in
                    CheckRow(isChecked: model.isChecked(essential.name)) {
                        model.toggleChecked(essential.name)
                    } label: {
                        Text("\(essential.name) × \(essential.count)")
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            .card()
        }
        .sheet(isPresented: $isAdding) {
            AddToBagSheet(model: model, recordsByID: recordsByID)
        }
    }

    private func itemRow(_ item: Item, closet: [Item]) -> some View {
        CheckRow(isChecked: model.isChecked(item.id)) {
            model.toggleChecked(item.id)
        } label: {
            HStack(spacing: 12) {
                ItemThumbnail(item: item, image: recordsByID[item.id]?.cutout, size: 48)
                Text(item.name).foregroundStyle(Theme.ink)
            }
        }
        .contextMenu {
            Button("Leave at home", systemImage: "minus.circle") {
                Task { await model.leaveOut(item, closet: closet) }
            }
        }
    }
}

/// A tappable row with a checkbox on the trailing edge.
private struct CheckRow<Label: View>: View {
    let isChecked: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            HStack {
                label
                Spacer(minLength: 8)
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? Theme.sageInk : Theme.line)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

// MARK: Stylist review

private struct CapsuleReviewCard: View {
    let model: TripModel
    let recordsByID: [String: ItemRecord]

    var body: some View {
        let closet = recordsByID.values.map(\.item)
        VStack(alignment: .leading, spacing: 12) {
            Label("Stylist check", systemImage: "sparkles")
                .font(Theme.title(18))
                .foregroundStyle(Theme.ink)
            switch model.review {
            case .idle:
                Text("Claude looks over the whole bag against your days: anything missing, a weak day, or a piece "
                    + "that isn't pulling its weight.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
                Button("Check my bag") { Task { await model.askForReview(closet: closet) } }
                    .buttonStyle(.pill(.accent))
            case .loading:
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.terracotta)
                    Text("The stylist is going through your bag…")
                        .font(.callout)
                        .foregroundStyle(Theme.inkMuted)
                }
            case let .reviewed(review):
                Text(review.verdict)
                    .font(.callout)
                    .foregroundStyle(Theme.ink)
                ForEach(review.changes) { change in
                    changeRow(change, closet: closet)
                }
            case let .failed(message):
                Text(message).font(.callout).foregroundStyle(Theme.terracotta)
                Button("Try again") { Task { await model.askForReview(closet: closet) } }
                    .buttonStyle(.pill(.quiet))
            }
        }
        .card()
    }

    private func changeRow(_ change: CapsuleReview.Change, closet: [Item]) -> some View {
        let name = { (id: String?) in id.flatMap { recordsByID[$0]?.item.name } }
        let title = switch (name(change.leaveOut), name(change.bring)) {
        case let (out?, bring?): "Swap \(out.lowercased()) for \(bring.lowercased())"
        case let (out?, nil): "Leave \(out.lowercased()) at home"
        case let (nil, bring?): "Bring \(bring.lowercased())"
        case (nil, nil): "Change the bag"
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(change.why)
                .font(.footnote)
                .foregroundStyle(Theme.inkMuted)
            Button("Apply") { Task { await model.apply(change, closet: closet) } }
                .buttonStyle(.pill(.quiet))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

// MARK: Add to bag

private struct AddToBagSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: TripModel
    let recordsByID: [String: ItemRecord]

    var body: some View {
        let packed = Set(model.details.packedItemIDs)
        let closet = recordsByID.values.map(\.item)
        let others = closet
            .filter { $0.category.isCore && !packed.contains($0.id) }
            .sorted { ($0.category.layerOrder, $0.name) < ($1.category.layerOrder, $1.name) }

        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12, alignment: .top)], spacing: 16) {
                    ForEach(others) { item in
                        Button {
                            dismiss()
                            Task { await model.bring(item, closet: closet) }
                        } label: {
                            VStack(spacing: 6) {
                                ItemThumbnail(item: item, image: recordsByID[item.id]?.cutout, size: 96)
                                Text(item.name)
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.gutter)
            }
            .editorialCanvas()
            .navigationTitle("Add to the bag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: Debrief

/// After the trip: how much of the bag got worn, or a prompt to say.
struct DebriefCard: View {
    let model: TripModel
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let share = model.wornShare, let debrief = model.details.debrief {
                Text("You wore \(debrief.wornItemIDs.count) of \(model.details.packedItemIDs.count) pieces")
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.ink)
                ProgressView(value: share).tint(share >= 0.9 ? Theme.sageInk : Theme.terracotta)
                Text(
                    share >= 0.9
                        ? "Nothing wasted. FitMe will pack like this again."
                        : "Pieces that came home unworn are less likely to be packed next time."
                )
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
                Button("Edit", action: onOpen).buttonStyle(.pill(.quiet))
            } else {
                Text("Back home? Tell FitMe what you actually wore.")
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.ink)
                Text("It learns which pieces earn their place in the bag.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
                Button("What did I wear?", action: onOpen).buttonStyle(.pill(.accent))
            }
        }
        .card()
    }
}

struct DebriefView: View {
    @Environment(\.dismiss) private var dismiss
    let model: TripModel
    let recordsByID: [String: ItemRecord]
    @State private var worn: Set<String>

    init(model: TripModel, recordsByID: [String: ItemRecord]) {
        self.model = model
        self.recordsByID = recordsByID
        // Start from the last answer, or from what trip mode logged as worn.
        _worn = State(initialValue: model.details.debrief?.wornItemIDs ?? model.details.plannedWornItemIDs)
    }

    var body: some View {
        let packed = model.details.packedItemIDs.compactMap { recordsByID[$0]?.item }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tap everything you wore at least once.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkMuted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12, alignment: .top)], spacing: 16) {
                        ForEach(packed) { item in
                            let isWorn = worn.contains(item.id)
                            Button {
                                if isWorn {
                                    worn.remove(item.id)
                                } else {
                                    worn.insert(item.id)
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ItemThumbnail(item: item, image: recordsByID[item.id]?.cutout, size: 96)
                                        .opacity(isWorn ? 1 : 0.45)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: isWorn ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(isWorn ? Theme.sageInk : Theme.inkMuted)
                                                .background(Theme.card, in: .circle)
                                                .padding(4)
                                        }
                                    Text(item.name)
                                        .font(.caption)
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isWorn ? .isSelected : [])
                        }
                    }
                }
                .padding(Theme.gutter)
            }
            .editorialCanvas()
            .navigationTitle("What did you wear?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveDebrief(wornItemIDs: worn)
                        dismiss()
                    }
                }
            }
        }
    }
}
