import FitEngine
import Foundation

/// Connects a trip's plan to `FitEngine`: packs a capsule, replans after edits, and finds swaps. The packing math is
/// slow enough (a second or two for a big closet) that it runs off the main actor.
struct TripPlanner: Sendable {
    var generator = OutfitGenerator()
    /// How many alternatives a swap offers.
    static let swapLimit = 6

    /// Packs the fewest pieces that dress every day, and plans each day's outfits.
    @concurrent
    func pack(
        _ details: TripDetails,
        closet: [Item],
        profile: StyleProfile,
        packedUnworn: [String: Int] = [:]
    ) async -> TripDetails {
        var options = options(for: details)
        options.packedUnworn = packedUnworn
        let result = PackingOptimizer(generator: generator, options: options)
            .pack(closet: Self.packable(closet), trip: Self.engineDays(details), profile: profile)
        return Self.applying(result, to: details)
    }

    /// Replans every day from `packedIDs`, e.g. after the user added or left out an item. Outfits already worn stay.
    @concurrent
    func replan(
        _ details: TripDetails,
        packedIDs: [String],
        closet: [Item],
        profile: StyleProfile
    ) async -> TripDetails {
        let ids = Set(packedIDs)
        let packed = Self.packable(closet).filter { ids.contains($0.id) }
        let result = PackingOptimizer(generator: generator, options: options(for: details))
            .plan(packed: packed, trip: Self.engineDays(details), profile: profile)
        return Self.applying(result, to: details)
    }

    /// Other outfits from the bag for one planned slot, best first.
    func alternatives(
        to planned: PlannedOutfit,
        in details: TripDetails,
        closet: [Item],
        profile: StyleProfile
    ) -> [ScoredOutfit] {
        guard let day = details.days[safe: planned.dayIndex] else { return [] }
        let ids = Set(details.packedItemIDs)
        let packed = Self.packable(closet).filter { ids.contains($0.id) }
        let context = OutfitContext(
            occasion: planned.occasion,
            weather: day.weather.dressFor,
            date: day.date,
            profile: profile
        )
        let current = Outfit(items: packed.filter { planned.itemIDs.contains($0.id) })
        return generator.alternatives(to: current, from: packed, context: context, limit: Self.swapLimit)
    }

    /// A planned outfit as the engine sees it, scored for its day.
    static func scored(
        _ planned: PlannedOutfit,
        in details: TripDetails,
        itemsByID: [String: Item],
        profile: StyleProfile? = nil
    ) -> ScoredOutfit? {
        let items = planned.itemIDs.compactMap { itemsByID[$0] }
        guard !items.isEmpty, let day = details.days[safe: planned.dayIndex] else { return nil }
        let outfit = Outfit(items: items)
        let context = OutfitContext(
            occasion: planned.occasion,
            weather: day.weather.dressFor,
            date: day.date,
            profile: profile
        )
        return ScoredOutfit(outfit: outfit, breakdown: OutfitScorer().score(outfit, context: context))
    }

    /// Per item: how many finished trips it was packed for and never worn.
    static func packedUnworn(from trips: [TripDetails]) -> [String: Int] {
        trips.flatMap(\.packedUnwornItemIDs).reduce(into: [:]) { counts, id in counts[id, default: 0] += 1 }
    }

    // MARK: Engine input

    func options(for details: TripDetails) -> PackingOptions {
        var options = details.luggage == .carryOn ? PackingOptions.carryOn : PackingOptions()
        options.laundryEveryNDays = details.laundry.everyNDays
        return options
    }

    static func engineDays(_ details: TripDetails) -> [TripDay] {
        details.days.map { TripDay(date: $0.date, weather: $0.weather.dressFor, occasions: $0.occasions) }
    }

    /// Everything can be packed: what's in the wash today will be clean by the trip.
    static func packable(_ closet: [Item]) -> [Item] {
        closet.map { item in
            var item = item
            item.isAvailable = true
            return item
        }
    }

    static func applying(_ result: PackingResult, to details: TripDetails) -> TripDetails {
        var updated = details
        updated.packedItemIDs = result.items.map(\.id)
        updated.outfitCount = result.outfitCount
        updated.outfits = result.assignments.map { assignment in
            let worn = details.outfits.first {
                $0.dayIndex == assignment.dayIndex && $0.occasion == assignment.occasion && $0.wornOn != nil
            }
            return worn ?? PlannedOutfit(
                dayIndex: assignment.dayIndex,
                occasion: assignment.occasion,
                itemIDs: assignment.outfit?.outfit.items.map(\.id) ?? []
            )
        }
        updated = markingRepeats(in: updated, items: result.items)
        // Keep ticks for what's still packed; essentials are ticked by name and always stay.
        let packed = Set(updated.packedItemIDs)
        let essentials = Set(Essentials.checklist(for: updated).map(\.name))
        updated.checkedOff = details.checkedOff.filter { packed.contains($0) || essentials.contains($0) }
        return updated
    }
}

extension TripPlanner {
    /// Flags outfits that wear a top, one-piece or statement piece already worn earlier in the same laundry cycle
    /// (the engine's rule for "fresh"), walking the days in order.
    static func markingRepeats(in details: TripDetails, items: [Item]) -> TripDetails {
        let byID = Dictionary(items.map { ($0.id, $0) }) { first, _ in first }
        let cycleLength = details.laundry.everyNDays ?? max(details.days.count, 1)
        var updated = details
        var usedByCycle: [Int: Set<String>] = [:]
        for index in updated.outfits.indices
            .sorted(by: { updated.outfits[$0].dayIndex < updated.outfits[$1].dayIndex }) {
            let cycle = updated.outfits[index].dayIndex / cycleLength
            let oncePerCycle = updated.outfits[index].itemIDs.filter { id in
                guard let item = byID[id] else { return false }
                return item.category == .top || item.category == .onePiece || item.isStatement
            }
            updated.outfits[index].repeatsAPiece = !usedByCycle[cycle, default: []].isDisjoint(with: oncePerCycle)
            usedByCycle[cycle, default: []].formUnion(oncePerCycle)
        }
        return updated
    }
}

extension Essentials {
    static func checklist(for details: TripDetails) -> [EssentialItem] {
        checklist(
            days: details.days.count,
            laundryEveryNDays: details.laundry.everyNDays,
            occasions: Set(details.days.flatMap(\.occasions))
        )
    }
}
