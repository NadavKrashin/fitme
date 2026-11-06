import FitEngine
import os
import SwiftData
import SwiftUI

/// A packed trip: the headline, today's outfit while traveling, the day-by-day plan and the packing list.
struct TripDetailView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.modelContext) private var modelContext
    let trip: TripRecord
    @State private var model: TripModel?

    var body: some View {
        Group {
            if let model {
                TripDetailContent(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(trip.name)
        .editorialCanvas()
        .task {
            if model == nil {
                model = dependencies.makeTripModel(trip, context: modelContext)
            }
        }
    }
}

private struct TripDetailContent: View {
    enum Tab: String, CaseIterable {
        case days = "Days"
        case packing = "Packing list"
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: TripModel
    @Query private var records: [ItemRecord]
    @State private var tab = Tab.days
    @State private var swapping: SwapTarget?
    @State private var isEditing = false
    @State private var isDebriefing = false

    var body: some View {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.itemID, $0) })
        let itemsByID = recordsByID.mapValues(\.item)
        let details = model.details

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                TripHeadline(details: details)
                if details.phase() == .ongoing, let today = details.dayIndex() {
                    todaySection(day: today, itemsByID: itemsByID, recordsByID: recordsByID)
                }
                if details.phase() == .finished || details.debrief != nil {
                    DebriefCard(model: model) { isDebriefing = true }
                }
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .days:
                    ForEach(details.days.indices, id: \.self) { day in
                        daySection(day, itemsByID: itemsByID, recordsByID: recordsByID)
                    }
                case .packing:
                    TripPackingList(model: model, recordsByID: recordsByID)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 80)
            .animation(.spring(duration: 0.4), value: model.details)
        }
        .overlay {
            if model.isReplanning {
                ProgressView().controlSize(.large).tint(Theme.terracotta)
            }
        }
        .toast(model.toast) { model.toast = nil }
        .toolbar {
            Menu("Trip options", systemImage: "ellipsis.circle") {
                Button("Edit trip", systemImage: "pencil") { isEditing = true }
                Button("What did I wear?", systemImage: "checklist") { isDebriefing = true }
                Button("Delete trip", systemImage: "trash", role: .destructive) { delete() }
            }
        }
        .sheet(isPresented: $isEditing) {
            TripWizardView(editing: model.record) { _ in model.reload() }
        }
        .sheet(isPresented: $isDebriefing) {
            DebriefView(model: model, recordsByID: recordsByID)
        }
        .sheet(item: $swapping) { target in
            SwapSheet(model: model, index: target.index, recordsByID: recordsByID)
        }
    }

    private func todaySection(
        day: Int,
        itemsByID: [String: Item],
        recordsByID: [String: ItemRecord]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Today in \(model.details.stop(forDay: day)?.place.name ?? "transit")")
            ForEach(outfitIndices(onDay: day), id: \.self) { index in
                TripOutfitCard(
                    planned: model.details.outfits[index],
                    details: model.details,
                    itemsByID: itemsByID,
                    recordsByID: recordsByID,
                    canWear: true,
                    onSwap: { swapping = SwapTarget(index: index) },
                    onWear: { model.wear(index, itemsByID: itemsByID) }
                )
            }
        }
    }

    private func daySection(_ day: Int, itemsByID: [String: Item], recordsByID: [String: ItemRecord]) -> some View {
        let plan = model.details.days[day]
        let isPast = Calendar.current.startOfDay(for: .now) >= plan.date
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day \(day + 1)")
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.ink)
                Text("\(plan.date.tripDay) · \(model.details.stop(forDay: day)?.place.name ?? "")")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 0)
            }
            Label(plan.weather.summary, systemImage: plan.weather.symbolName)
                .font(.footnote)
                .foregroundStyle(Theme.inkMuted)
            ForEach(outfitIndices(onDay: day), id: \.self) { index in
                TripOutfitCard(
                    planned: model.details.outfits[index],
                    details: model.details,
                    itemsByID: itemsByID,
                    recordsByID: recordsByID,
                    canWear: isPast,
                    onSwap: { swapping = SwapTarget(index: index) },
                    onWear: { model.wear(index, itemsByID: itemsByID, on: plan.date) }
                )
            }
        }
    }

    private func outfitIndices(onDay day: Int) -> [Int] {
        model.details.outfits.indices.filter { model.details.outfits[$0].dayIndex == day }
    }

    private func delete() {
        modelContext.delete(model.record)
        do {
            try modelContext.save()
        } catch {
            Logger.trips.error("Couldn't delete the trip: \(String(describing: error))")
        }
        dismiss()
    }
}

// MARK: Headline

private struct TripHeadline: View {
    let details: TripDetails

    var body: some View {
        let uncovered = details.outfits.count(where: { !$0.isCovered })
        let repeats = details.outfits.count(where: \.repeatsAPiece)
        VStack(alignment: .leading, spacing: 10) {
            Text("\(details.dateRange) · \(details.dayCountText)")
                .font(.subheadline)
                .foregroundStyle(Theme.inkMuted)
            Text("\(details.packedItemIDs.count) pieces → \(details.outfitCount) outfits")
                .font(Theme.display(30))
                .foregroundStyle(Theme.ink)
            if uncovered == 0 {
                Label(
                    "Dresses all \(details.outfits.count) plans across \(details.dayCountText)",
                    systemImage: "checkmark.seal"
                )
                .font(.subheadline)
                .foregroundStyle(Theme.sageInk)
            } else {
                Label(
                    "\(uncovered) plan\(uncovered == 1 ? "" : "s") need\(uncovered == 1 ? "s" : "") something your "
                        + "closet doesn't have",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.subheadline)
                .foregroundStyle(Theme.terracotta)
            }
            if repeats > 0 {
                Label(
                    "\(repeats) outfit\(repeats == 1 ? "" : "s") repeat\(repeats == 1 ? "s" : "") a top before it's "
                        + "washed. Add a top, or plan laundry.",
                    systemImage: "arrow.uturn.backward"
                )
                .font(.subheadline)
                .foregroundStyle(Theme.butterInk)
            }
            HStack(spacing: 6) {
                Badge(text: details.luggage.title)
                Badge(text: details.laundry.title, tint: (Theme.butter, Theme.butterInk))
            }
        }
        .card(padding: 20)
    }
}

// MARK: Outfit card

/// One planned outfit: occasion, flat-lay, swap and (in trip mode) wear.
private struct TripOutfitCard: View {
    let planned: PlannedOutfit
    let details: TripDetails
    let itemsByID: [String: Item]
    let recordsByID: [String: ItemRecord]
    let canWear: Bool
    let onSwap: () -> Void
    let onWear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Badge(text: planned.occasion.title, tint: Theme.tint(for: planned.occasion))
            if let scored = TripPlanner.scored(planned, in: details, itemsByID: itemsByID) {
                OutfitCollage(outfit: scored.outfit, image: { recordsByID[$0]?.cutout }, height: 200)
                Text(OutfitCard.title(for: scored.outfit))
                    .font(Theme.title(17))
                    .foregroundStyle(Theme.ink)
                if let extras = OutfitCard.extras(for: scored.outfit) {
                    Text(extras).font(.footnote).foregroundStyle(Theme.inkMuted)
                }
                if planned.repeatsAPiece {
                    Badge(text: "Repeats a top", tint: (Theme.butter, Theme.butterInk))
                }
                HStack(spacing: 10) {
                    Button("Swap", systemImage: "arrow.triangle.2.circlepath", action: onSwap)
                        .buttonStyle(.pill(.quiet))
                    Spacer()
                    if planned.wornOn != nil {
                        Label("Worn", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.sageInk)
                    } else if canWear {
                        Button("Wear this", systemImage: "tshirt", action: onWear)
                            .buttonStyle(.pill(.primary))
                    }
                }
            } else {
                Text("Nothing in the bag suits this. Add a piece from the packing list, or ask the stylist.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .card()
    }
}

// MARK: Swap

private struct SwapSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: TripModel
    let index: Int
    let recordsByID: [String: ItemRecord]

    var body: some View {
        let alternatives = model.alternatives(to: index, closet: recordsByID.values.map(\.item))
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if alternatives.isEmpty {
                        Text("Nothing else in the bag works for this. Add a piece from the packing list.")
                            .font(.callout)
                            .foregroundStyle(Theme.inkMuted)
                            .card()
                    }
                    ForEach(alternatives) { alternative in
                        VStack(alignment: .leading, spacing: 12) {
                            OutfitCollage(outfit: alternative.outfit, image: { recordsByID[$0]?.cutout }, height: 180)
                            Text(OutfitCard.title(for: alternative.outfit))
                                .font(Theme.title(17))
                                .foregroundStyle(Theme.ink)
                            if let extras = OutfitCard.extras(for: alternative.outfit) {
                                Text(extras).font(.footnote).foregroundStyle(Theme.inkMuted)
                            }
                            Button("Wear this instead") {
                                model.swap(index, to: alternative.outfit, closet: recordsByID.values.map(\.item))
                                dismiss()
                            }
                            .buttonStyle(.pill(.primary))
                        }
                        .card()
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .editorialCanvas()
            .navigationTitle("From your bag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The planned outfit being swapped, as a sheet item.
private struct SwapTarget: Identifiable {
    let index: Int

    var id: Int {
        index
    }
}
