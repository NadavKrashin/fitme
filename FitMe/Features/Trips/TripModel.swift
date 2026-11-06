import FitEngine
import Foundation
import Observation
import os
import SwiftData

/// One packed trip: its day plan and packing list, edits to the bag, trip mode, the stylist's review and the debrief.
@MainActor
@Observable
final class TripModel {
    enum ReviewState: Equatable {
        case idle
        case loading
        case reviewed(CapsuleReview)
        case failed(String)
    }

    let record: TripRecord
    private(set) var details: TripDetails
    private(set) var review: ReviewState = .idle
    /// True while the days are being replanned after an edit to the bag.
    private(set) var isReplanning = false
    var toast: Toast?

    private let planner: TripPlanner
    private let reviewer: any CapsuleReviewing
    private let context: ModelContext

    init(record: TripRecord, planner: TripPlanner, reviewer: any CapsuleReviewing, context: ModelContext) {
        self.record = record
        details = record.details
        self.planner = planner
        self.reviewer = reviewer
        self.context = context
    }

    /// Picks up changes made elsewhere, e.g. the trip was edited and repacked.
    func reload() {
        details = record.details
    }

    // MARK: Packing list

    func isChecked(_ key: String) -> Bool {
        details.checkedOff.contains(key)
    }

    /// Ticks an item id or essential name off the packing list, or unticks it.
    func toggleChecked(_ key: String) {
        var updated = details
        if updated.checkedOff.remove(key) == nil {
            updated.checkedOff.insert(key)
        }
        commit(updated)
    }

    /// Leaves an item at home and replans the days without it.
    func leaveOut(_ item: Item, closet: [Item]) async {
        await changeBag(
            packedIDs: details.packedItemIDs.filter { $0 != item.id },
            closet: closet,
            toast: Toast(symbol: "minus.circle", message: "\(item.name) stays home")
        )
    }

    /// Adds a closet item to the bag and replans the days with it.
    func bring(_ item: Item, closet: [Item]) async {
        guard !details.packedItemIDs.contains(item.id) else { return }
        await changeBag(
            packedIDs: details.packedItemIDs + [item.id],
            closet: closet,
            toast: Toast(symbol: "plus.circle", message: "Packed \(item.name.lowercased())")
        )
    }

    /// Applies one of the stylist's suggestions.
    func apply(_ change: CapsuleReview.Change, closet: [Item]) async {
        var ids = details.packedItemIDs.filter { $0 != change.leaveOut }
        if let bring = change.bring, !ids.contains(bring) {
            ids.append(bring)
        }
        let names = Dictionary(uniqueKeysWithValues: closet.map { ($0.id, $0.name) })
        let message = switch (change.leaveOut.flatMap { names[$0] }, change.bring.flatMap { names[$0] }) {
        case let (out?, bring?): "Swapped \(out.lowercased()) for \(bring.lowercased())"
        case let (out?, nil): "\(out) stays home"
        case let (nil, bring?): "Packed \(bring.lowercased())"
        case (nil, nil): "Bag updated"
        }
        await changeBag(packedIDs: ids, closet: closet, toast: Toast(symbol: "sparkles", message: message))
        if case var .reviewed(current) = review {
            current.changes.removeAll { $0 == change }
            review = .reviewed(current)
        }
    }

    private func changeBag(packedIDs: [String], closet: [Item], toast: Toast) async {
        let before = details
        isReplanning = true
        let replanned = await planner.replan(
            details,
            packedIDs: packedIDs,
            closet: closet,
            profile: FeedbackRecorder(context: context).profile()
        )
        isReplanning = false
        commit(replanned)
        var withUndo = toast
        withUndo.undo = { [weak self] in self?.commit(before) }
        self.toast = withUndo
    }

    // MARK: Day plan

    func alternatives(to index: Int, closet: [Item]) -> [ScoredOutfit] {
        guard let planned = details.outfits[safe: index] else { return [] }
        return planner.alternatives(
            to: planned,
            in: details,
            closet: closet,
            profile: FeedbackRecorder(context: context).profile()
        )
    }

    /// Replaces one planned outfit with another from the bag.
    func swap(_ index: Int, to outfit: Outfit, closet: [Item]) {
        guard details.outfits.indices.contains(index) else { return }
        var updated = details
        updated.outfits[index].itemIDs = outfit.items.map(\.id)
        commit(TripPlanner.markingRepeats(in: updated, items: closet))
        toast = Toast(symbol: "arrow.triangle.2.circlepath", message: "Outfit swapped")
    }

    /// Trip mode: logs a planned outfit as worn, which also counts toward each piece's wear history.
    func wear(_ index: Int, itemsByID: [String: Item], on date: Date = .now) {
        guard let planned = details.outfits[safe: index], planned.wornOn == nil else { return }
        var updated = details
        updated.outfits[index].wornOn = date
        commit(updated)
        let items = planned.itemIDs.compactMap { itemsByID[$0] }
        if !items.isEmpty {
            FeedbackRecorder(context: context).record(.wore, for: Outfit(items: items), on: date)
        }
        toast = Toast(symbol: "checkmark.circle.fill", message: "Logged as worn")
    }

    // MARK: Stylist review

    func askForReview(closet: [Item]) async {
        review = .loading
        do {
            review = try await .reviewed(reviewer.review(details, closet: closet))
        } catch {
            review = .failed((error as? ClaudeError)?.userMessage ?? "The stylist couldn't answer. Try again.")
        }
    }

    // MARK: Debrief

    func saveDebrief(wornItemIDs: Set<String>, on date: Date = .now) {
        var updated = details
        updated.debrief = TripDebrief(wornItemIDs: wornItemIDs.intersection(details.packedItemIDs), completedAt: date)
        commit(updated)
    }

    /// Share of packed items that were worn, once the debrief is done.
    var wornShare: Double? {
        guard let debrief = details.debrief, !details.packedItemIDs.isEmpty else { return nil }
        return Double(debrief.wornItemIDs.count) / Double(details.packedItemIDs.count)
    }

    // MARK: Storage

    private func commit(_ updated: TripDetails) {
        details = updated
        record.details = updated
        do {
            try context.save()
        } catch {
            Logger.trips.error("Couldn't save the trip: \(String(describing: error))")
        }
    }
}
