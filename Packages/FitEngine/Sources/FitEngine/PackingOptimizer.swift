import Foundation

/// Picks the capsule of items that covers every day of a trip with good outfits, using as little suitcase as possible.
///
/// Greedy marginal gain: repeatedly add the item that unlocks the most new good outfits for the slots that still
/// need them, per unit of packing cost. When no single item helps (e.g. a formal dinner needs new shoes *and* a
/// new outfit), a whole outfit is added at once. A final pass drops anything that turned out redundant.
///
/// "Covered" means every slot in a laundry cycle gets its own top or one-piece, and statement pieces aren't repeated
/// within a cycle; plain bottoms, shoes and layers repeat.
public struct PackingOptimizer: Sendable {
    public var generator: OutfitGenerator
    public var options: PackingOptions

    /// Safety stop for the greedy loop; real trips converge in well under this.
    private static let maxIterations = 100
    /// Gains below this are rounding noise, not real improvements.
    private static let gainEpsilon = 1e-9
    /// Score points an injected outfit earns per item it reuses from the capsule.
    private static let reuseBonus = 6.0
    /// Beam width when searching the whole closet for an outfit to inject.
    private static let injectionBeamWidth = 120

    public init(generator: OutfitGenerator = OutfitGenerator(), options: PackingOptions = PackingOptions()) {
        self.generator = generator
        self.options = options
    }

    public func pack(closet: [Item], trip: [TripDay], profile: StyleProfile? = nil) -> PackingResult {
        let plan = TripPlan(trip: trip, laundryEveryNDays: options.laundryEveryNDays, profile: profile)
        let candidates = closet
            .filter { item in plan.groups.contains { Rules.isEligible(item, for: $0.context) } }
            .sorted { $0.id < $1.id }

        var capsule: [Item] = []
        var states: GroupStates = plan.groups.map { _ in [:] }
        var exhausted = Set<Int>()

        for _ in 0 ..< Self.maxIterations {
            let current = match(states, plan: plan)
            let deficient = current.unfilled.keys.filter { !exhausted.contains($0) }
            guard let neediest = deficient.max(by: { a, b in
                (current.unfilled[a, default: 0], b) < (current.unfilled[b, default: 0], a)
            }) else { break }

            if let step = bestSingleItem(candidates: candidates, capsule: capsule, states: states, plan: plan) {
                capsule.append(step.item)
                states = step.states
                continue
            }

            // Nothing helps alone: add a whole outfit for the neediest group, reusing what's packed.
            let usedBases = Set(states.flatMap { $0.values.map(\.outfit.baseKey) })
            if let outfit = injection(
                for: plan.groups[neediest],
                capsule: capsule,
                closet: candidates,
                usedBases: usedBases
            ) {
                capsule.append(contentsOf: outfit.outfit.items.filter { !capsule.contains($0) })
                states = recompute(capsule: capsule, groups: plan.groups)
            } else {
                exhausted.insert(neediest)
            }
        }

        capsule = pruned(capsule, plan: plan)
        return assemble(capsule: capsule, trip: trip, plan: plan)
    }

    // MARK: Greedy step

    /// Per group: the best good outfit for each distinct base (top / one-piece).
    typealias GroupStates = [[String: ScoredOutfit]]

    private func bestSingleItem(
        candidates: [Item],
        capsule: [Item],
        states: GroupStates,
        plan: TripPlan
    ) -> (item: Item, states: GroupStates)? {
        let currentValue = match(states, plan: plan).value
        var best: (item: Item, states: GroupStates)?
        var bestRatio = 0.0

        for item in candidates where !capsule.contains(item) && fitsLimits(capsule + [item]) {
            var newStates = states
            for g in plan.groups.indices where Rules.isEligible(item, for: plan.groups[g].context) {
                let unlocked = generator.allOutfits(
                    from: capsule + [item],
                    context: plan.groups[g].context,
                    mustInclude: item,
                    minScore: options.scoreThreshold
                )
                newStates[g] = merged(states[g], with: unlocked)
            }
            let gain = match(newStates, plan: plan).value - currentValue
            let ratio = gain / item.packingCost
            if gain > Self.gainEpsilon, ratio > bestRatio {
                best = (item, newStates)
                bestRatio = ratio
            }
        }
        return best
    }

    private func injection(
        for group: TripPlan.Group,
        capsule: [Item],
        closet: [Item],
        usedBases: Set<String>
    ) -> ScoredOutfit? {
        let wide = OutfitGenerator(
            scorer: generator.scorer,
            beamWidth: max(generator.beamWidth, Self.injectionBeamWidth)
        )
        let reuseRank = { (outfit: ScoredOutfit) -> Double in
            outfit.score + Self.reuseBonus * Double(outfit.outfit.items.filter(capsule.contains).count)
        }
        return wide.build(from: closet, context: group.context, mustInclude: nil, beam: wide.beamWidth)
            .filter { $0.score >= options.scoreThreshold && !usedBases.contains($0.outfit.baseKey) }
            .filter { fitsLimits(capsule + $0.outfit.items.filter { !capsule.contains($0) }) }
            .max { (reuseRank($0), $1.id) < (reuseRank($1), $0.id) }
    }

    // MARK: Objective

    /// Items worn at most once per laundry cycle: the top or one-piece, plus any statement piece (a repeated red
    /// trouser reads as "the same outfit again" even with a different shirt).
    static func oncePerCycle(_ outfit: Outfit) -> [String] {
        Array(Set([outfit.baseKey] + outfit.items.filter(\.isStatement).map(\.id))).sorted()
    }

    /// Keeps the best outfit per once-per-cycle combination, so a base's version without a statement piece survives
    /// alongside the one with it.
    private func merged(_ state: [String: ScoredOutfit], with outfits: [ScoredOutfit]) -> [String: ScoredOutfit] {
        var result = state
        for outfit in outfits {
            let key = Self.oncePerCycle(outfit.outfit).joined(separator: "|")
            if let current = result[key], !OutfitGenerator.ranking(outfit, current) {
                continue
            }
            result[key] = outfit
        }
        return result
    }

    /// Gives each slot its own base (and statement pieces) within a laundry cycle, scarcest groups first.
    /// Coverage dominates (1 per filled slot); quality breaks ties (up to 0.5 more each).
    private func match(_ states: GroupStates, plan: TripPlan) -> (value: Double, unfilled: [Int: Int]) {
        var value = 0.0
        var unfilled: [Int: Int] = [:]
        for cycle in plan.cycles {
            var used = Set<String>()
            let scarcestFirst = cycle.sorted {
                (states[plan.slots[$0].group].count, $0) < (states[plan.slots[$1].group].count, $1)
            }
            for slotIndex in scarcestFirst {
                let group = plan.slots[slotIndex].group
                let pick = states[group].values
                    .filter { used.isDisjoint(with: Self.oncePerCycle($0.outfit)) }
                    .max { OutfitGenerator.ranking($1, $0) }
                if let pick {
                    used.formUnion(Self.oncePerCycle(pick.outfit))
                    value += 1 + 0.5 * pick.score / 100
                } else {
                    unfilled[group, default: 0] += 1
                }
            }
        }
        return (value, unfilled)
    }

    private func recompute(capsule: [Item], groups: [TripPlan.Group]) -> GroupStates {
        groups.map {
            merged(
                [:],
                with: generator.allOutfits(from: capsule, context: $0.context, minScore: options.scoreThreshold)
            )
        }
    }

    private func fitsLimits(_ items: [Item]) -> Bool {
        if let maxItems = options.maxItems, items.count > maxItems {
            return false
        }
        return items.count(where: { $0.category == .shoes }) <= options.maxShoes
            && items.count(where: { $0.category == .outerwear }) <= options.maxOuterwear
    }

    /// Drops items whose removal doesn't lower the objective, most expensive first.
    private func pruned(_ capsule: [Item], plan: TripPlan) -> [Item] {
        var current = capsule
        var currentValue = match(recompute(capsule: current, groups: plan.groups), plan: plan).value
        for item in capsule.sorted(by: { ($0.packingCost, $1.id) > ($1.packingCost, $0.id) }) {
            let without = current.filter { $0 != item }
            let value = match(recompute(capsule: without, groups: plan.groups), plan: plan).value
            if value >= currentValue - Self.gainEpsilon {
                current = without
                currentValue = value
            }
        }
        return current
    }

    // MARK: Day plan

    private func assemble(capsule: [Item], trip: [TripDay], plan: TripPlan) -> PackingResult {
        let outfitsByGroup = plan.groups.map {
            generator.allOutfits(from: capsule, context: $0.context, minScore: options.scoreThreshold)
        }
        let baseCounts = outfitsByGroup.map { Set($0.map(\.outfit.baseKey)).count }
        var picks: [Int: (outfit: ScoredOutfit, overLimit: Bool)] = [:]

        for cycle in plan.cycles {
            var wears: [String: Int] = [:]
            let scarcestFirst = cycle.sorted {
                (baseCounts[plan.slots[$0].group], $0) < (baseCounts[plan.slots[$1].group], $1)
            }
            for slotIndex in scarcestFirst {
                let candidates = outfitsByGroup[plan.slots[slotIndex].group]
                let withinLimits = candidates.filter { isWithinWearLimits($0.outfit, wears: wears) }
                let pick = withinLimits.max { (adjusted($0, wears), $1.id) < (adjusted($1, wears), $0.id) }
                    ?? candidates.min { leastWorn($0, $1, wears: wears) }
                guard let pick else { continue }
                for item in pick.outfit.items {
                    wears[item.id, default: 0] += 1
                }
                picks[slotIndex] = (pick, !withinLimits.contains(pick))
            }
        }

        let assignments = plan.slots.enumerated().map { index, slot in
            SlotAssignment(
                dayIndex: slot.dayIndex,
                date: trip[slot.dayIndex].date,
                occasion: slot.occasion,
                outfit: picks[index]?.outfit,
                exceedsWearLimit: picks[index]?.overLimit ?? false
            )
        }
        return PackingResult(
            items: capsule.sorted { ($0.category.layerOrder, $0.id) < ($1.category.layerOrder, $1.id) },
            assignments: assignments,
            outfitCount: Set(outfitsByGroup.flatMap { $0.map(\.id) }).count
        )
    }

    private func isWithinWearLimits(_ outfit: Outfit, wears: [String: Int]) -> Bool {
        let fresh = Self.oncePerCycle(outfit).allSatisfy { wears[$0, default: 0] < 1 }
        let bottomOK = outfit.bottom.map { wears[$0.id, default: 0] < options.maxWearsPerBottom } ?? true
        return fresh && bottomOK
    }

    /// Repeating bottoms and shoes is fine, but spread the wear when there's a choice.
    private func adjusted(_ outfit: ScoredOutfit, _ wears: [String: Int]) -> Double {
        outfit.score - 2 * Double(outfit.outfit.items.map { wears[$0.id, default: 0] }.reduce(0, +))
    }

    /// Fallback ordering when every option breaks a wear limit: least-worn base, then best score.
    private func leastWorn(_ a: ScoredOutfit, _ b: ScoredOutfit, wears: [String: Int]) -> Bool {
        (wears[a.outfit.baseKey, default: 0], -a.score, a.id) < (wears[b.outfit.baseKey, default: 0], -b.score, b.id)
    }
}

/// A trip broken into outfit slots, grouped so slots with the same needs can share outfits.
struct TripPlan {
    /// Slots that share an occasion and weather band.
    struct Group {
        let context: OutfitContext
    }

    struct Slot {
        let dayIndex: Int
        let occasion: Occasion
        let group: Int
    }

    let groups: [Group]
    let slots: [Slot]
    /// Slot indices per laundry cycle. A top or one-piece is worn at most once per cycle.
    let cycles: [[Int]]

    init(trip: [TripDay], laundryEveryNDays: Int?, profile: StyleProfile?) {
        var groupIndex: [String: Int] = [:]
        var groupOccasions: [Occasion] = []
        var groupDays: [[TripDay]] = []
        var slots: [Slot] = []

        for (dayIndex, day) in trip.enumerated() {
            for occasion in day.occasions {
                let key = "\(occasion.rawValue)@\(day.weather.bandKey)"
                let group = groupIndex[key] ?? groupDays.count
                if group == groupDays.count {
                    groupIndex[key] = group
                    groupOccasions.append(occasion)
                    groupDays.append([])
                }
                groupDays[group].append(day)
                slots.append(Slot(dayIndex: dayIndex, occasion: occasion, group: group))
            }
        }

        // Each group dresses for its harshest day, and is never empty by construction.
        groups = zip(groupOccasions, groupDays).map { occasion, days in
            let weather = days.dropFirst().reduce(days[0].weather) { $0.harsher(with: $1.weather) }
            return Group(context: OutfitContext(
                occasion: occasion,
                weather: weather,
                date: days[0].date,
                profile: profile
            ))
        }
        self.slots = slots

        let cycleLength = laundryEveryNDays ?? max(trip.count, 1)
        cycles = Dictionary(grouping: slots.indices) { slots[$0].dayIndex / cycleLength }
            .sorted { $0.key < $1.key }
            .map(\.value)
    }
}
