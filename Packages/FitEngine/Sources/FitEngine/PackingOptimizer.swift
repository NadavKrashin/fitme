import Foundation

public struct TripDay: Codable, Hashable {
    public var date: Date
    public var weather: Weather
    /// What the day holds, in order (e.g. sightseeing, then dinner).
    public var occasions: [Occasion]

    public init(date: Date, weather: Weather, occasions: [Occasion]) {
        self.date = date
        self.weather = weather
        self.occasions = occasions
    }
}

public struct PackingOptions {
    public var maxShoes = 3
    public var maxOuterwear = 2
    public var maxItems: Int?
    /// Minimum score for an outfit to count as "good enough to plan a day around".
    public var scoreThreshold = 62.0
    /// Wash every N days; nil means no laundry during the trip.
    public var laundryEveryNDays: Int?
    /// Tops and one-pieces are worn once per laundry cycle; bottoms and shoes can repeat.
    public var maxWearsPerBottom = 3

    public init() {}
}

/// One outfit slot on one day of the trip.
public struct SlotAssignment: Hashable {
    public var dayIndex: Int
    public var date: Date
    public var occasion: Occasion
    public var outfit: ScoredOutfit?
    /// True when the only option repeats a piece beyond the wear limits.
    public var exceedsWearLimit: Bool
}

public struct PackingResult {
    public var items: [Item]
    public var assignments: [SlotAssignment]
    /// Distinct good outfits the packed items make across the whole trip.
    public var outfitCount: Int

    public var uncovered: [SlotAssignment] { assignments.filter { $0.outfit == nil } }
    public var summary: String { "\(items.count) items → \(outfitCount) outfits → \(assignments.count - uncovered.count)/\(assignments.count) slots covered" }
}

/// Picks the capsule of items that covers every day of a trip with good outfits, using as little suitcase as possible.
///
/// Greedy marginal gain: repeatedly add the item that unlocks the most new good outfits for the slots that still
/// need them, per unit of packing cost. When no single item helps (e.g. a formal dinner needs new shoes *and* a
/// new outfit), a whole outfit is added at once. A final pass drops anything that turned out redundant.
///
/// "Covered" means every slot in a laundry cycle gets its own top or one-piece; bottoms, shoes and layers repeat.
public struct PackingOptimizer {
    public var generator: OutfitGenerator
    public var options: PackingOptions

    public init(generator: OutfitGenerator = OutfitGenerator(), options: PackingOptions = PackingOptions()) {
        self.generator = generator
        self.options = options
    }

    /// Slots that share an occasion and weather band, and can therefore share outfits.
    struct Group {
        let key: String
        let context: OutfitContext
    }

    struct Slot {
        let dayIndex: Int
        let occasion: Occasion
        let group: Int
    }

    struct Plan {
        var groups: [Group] = []
        var slots: [Slot] = []
        /// Slot indices per laundry cycle. A top or one-piece is worn at most once per cycle.
        var cycles: [[Int]] = []
    }

    /// Per group: the best good outfit for each distinct base (top / one-piece).
    typealias States = [[String: ScoredOutfit]]

    public func pack(closet: [Item], trip: [TripDay], profile: StyleProfile? = nil) -> PackingResult {
        let plan = makePlan(trip: trip, profile: profile)
        let groups = plan.groups
        let candidates = closet.filter { item in groups.contains { Rules.isEligible(item, for: $0.context) } }
            .sorted { $0.id < $1.id }

        var capsule: [Item] = []
        var states: States = groups.map { _ in [:] }
        var exhausted = Set<Int>()

        for _ in 0..<100 {
            let current = match(states, plan: plan)
            let deficient = current.unfilled.keys.filter { !exhausted.contains($0) }.sorted()
            if deficient.isEmpty { break }

            // 1. Best single item by gain per cost.
            var best: (item: Item, ratio: Double, states: States)?
            for item in candidates where !capsule.contains(item) && fitsLimits(capsule + [item]) {
                var newStates = states
                for g in groups.indices where Rules.isEligible(item, for: groups[g].context) {
                    let found = generator.allOutfits(from: capsule + [item], context: groups[g].context,
                                                     mustInclude: item, minScore: options.scoreThreshold)
                    newStates[g] = merged(states[g], with: found)
                }
                let gain = match(newStates, plan: plan).value - current.value
                let ratio = gain / item.packingCost
                if gain > 1e-9, ratio > (best?.ratio ?? 0) {
                    best = (item, ratio, newStates)
                }
            }
            if let best {
                capsule.append(best.item)
                states = best.states
                continue
            }

            // 2. Nothing helps alone: add the best whole outfit for the neediest group, reusing what's packed.
            let g = deficient.max { (current.unfilled[$0]!, $1) < (current.unfilled[$1]!, $0) }!
            let usedBases = Set(states.flatMap(\.keys))
            if let outfit = injection(for: groups[g], capsule: capsule, closet: candidates, usedBases: usedBases) {
                capsule.append(contentsOf: outfit.outfit.items.filter { !capsule.contains($0) })
                states = recompute(capsule: capsule, groups: groups)
            } else {
                exhausted.insert(g)
            }
        }

        capsule = pruned(capsule, plan: plan)
        return assemble(capsule: capsule, trip: trip, plan: plan)
    }

    // MARK: Plan

    private func makePlan(trip: [TripDay], profile: StyleProfile?) -> Plan {
        var plan = Plan()
        var groupIndex: [String: Int] = [:]
        var groupDays: [[TripDay]] = []
        for (i, day) in trip.enumerated() {
            for occasion in day.occasions {
                let key = "\(occasion.rawValue)@\(day.weather.bandKey)"
                if groupIndex[key] == nil {
                    groupIndex[key] = plan.groups.count
                    plan.groups.append(Group(key: key, context: OutfitContext(occasion: occasion, date: day.date, profile: profile)))
                    groupDays.append([])
                }
                groupDays[groupIndex[key]!].append(day)
                plan.slots.append(Slot(dayIndex: i, occasion: occasion, group: groupIndex[key]!))
            }
        }
        // Plan each group for its harshest day: coldest and wettest.
        for g in plan.groups.indices {
            plan.groups[g] = Group(key: plan.groups[g].key, context: OutfitContext(
                occasion: plan.groups[g].context.occasion,
                weather: Weather(
                    feelsLikeC: groupDays[g].map(\.weather.feelsLikeC).min()!,
                    precipitationChance: groupDays[g].map(\.weather.precipitationChance).max()!
                ),
                date: plan.groups[g].context.date,
                profile: profile
            ))
        }
        let cycleLength = options.laundryEveryNDays ?? max(trip.count, 1)
        let byCycle = Dictionary(grouping: plan.slots.indices, by: { plan.slots[$0].dayIndex / cycleLength })
        plan.cycles = byCycle.keys.sorted().map { byCycle[$0]! }
        return plan
    }

    // MARK: Objective

    private func merged(_ state: [String: ScoredOutfit], with outfits: [ScoredOutfit]) -> [String: ScoredOutfit] {
        var result = state
        for outfit in outfits {
            let key = outfit.outfit.baseKey
            if let current = result[key], !OutfitGenerator.ranking(outfit, current) { continue }
            result[key] = outfit
        }
        return result
    }

    /// Gives each slot its own base within a laundry cycle, scarcest groups first.
    /// Coverage dominates (1 per filled slot); quality breaks ties (up to 0.5 more each).
    private func match(_ states: States, plan: Plan) -> (value: Double, unfilled: [Int: Int]) {
        var value = 0.0
        var unfilled: [Int: Int] = [:]
        for cycle in plan.cycles {
            var used = Set<String>()
            let order = cycle.sorted { (states[plan.slots[$0].group].count, $0) < (states[plan.slots[$1].group].count, $1) }
            for s in order {
                let g = plan.slots[s].group
                let pick = states[g].values
                    .filter { !used.contains($0.outfit.baseKey) }
                    .max { OutfitGenerator.ranking($1, $0) }
                if let pick {
                    used.insert(pick.outfit.baseKey)
                    value += 1 + 0.5 * pick.score / 100
                } else {
                    unfilled[g, default: 0] += 1
                }
            }
        }
        return (value, unfilled)
    }

    private func recompute(capsule: [Item], groups: [Group]) -> States {
        groups.map { merged([:], with: generator.allOutfits(from: capsule, context: $0.context, minScore: options.scoreThreshold)) }
    }

    private func fitsLimits(_ items: [Item]) -> Bool {
        if let max = options.maxItems, items.count > max { return false }
        return items.filter { $0.category == .shoes }.count <= options.maxShoes
            && items.filter { $0.category == .outerwear }.count <= options.maxOuterwear
    }

    private func injection(for group: Group, capsule: [Item], closet: [Item], usedBases: Set<String>) -> ScoredOutfit? {
        let wide = OutfitGenerator(scorer: generator.scorer, beamWidth: max(generator.beamWidth, 120))
        let options = wide.build(from: closet, context: group.context, mustInclude: nil, beam: wide.beamWidth)
            .filter { $0.score >= self.options.scoreThreshold && !usedBases.contains($0.outfit.baseKey) }
            .filter { fitsLimits(capsule + $0.outfit.items.filter { !capsule.contains($0) }) }
        // Prefer outfits that reuse packed items: each reused item is worth a few score points.
        return options.max { a, b in
            let ra = a.score + 6 * Double(a.outfit.items.filter(capsule.contains).count)
            let rb = b.score + 6 * Double(b.outfit.items.filter(capsule.contains).count)
            return ra != rb ? ra < rb : a.id > b.id
        }
    }

    /// Drops items whose removal doesn't lower the objective, most expensive first.
    private func pruned(_ capsule: [Item], plan: Plan) -> [Item] {
        var current = capsule
        var currentValue = match(recompute(capsule: current, groups: plan.groups), plan: plan).value
        for item in capsule.sorted(by: { ($0.packingCost, $1.id) > ($1.packingCost, $0.id) }) {
            let without = current.filter { $0 != item }
            let v = match(recompute(capsule: without, groups: plan.groups), plan: plan).value
            if v >= currentValue - 1e-9 {
                current = without
                currentValue = v
            }
        }
        return current
    }

    // MARK: Day plan

    private func assemble(capsule: [Item], trip: [TripDay], plan: Plan) -> PackingResult {
        let outfitsByGroup = plan.groups.map {
            generator.allOutfits(from: capsule, context: $0.context, minScore: options.scoreThreshold)
        }
        let baseCounts = outfitsByGroup.map { Set($0.map(\.outfit.baseKey)).count }
        var picks: [Int: (outfit: ScoredOutfit?, overLimit: Bool)] = [:]

        for cycle in plan.cycles {
            var wears: [String: Int] = [:]
            let order = cycle.sorted { (baseCounts[plan.slots[$0].group], $0) < (baseCounts[plan.slots[$1].group], $1) }
            for s in order {
                let candidates = outfitsByGroup[plan.slots[s].group]
                let withinLimits = candidates.filter { candidate in
                    let o = candidate.outfit
                    return (wears[o.baseKey] ?? 0) < 1
                        && (o.bottom.map { (wears[$0.id] ?? 0) < options.maxWearsPerBottom } ?? true)
                }
                let pick = withinLimits.max { (adjusted($0, wears), $1.id) < (adjusted($1, wears), $0.id) }
                    ?? candidates.min {
                        (wears[$0.outfit.baseKey] ?? 0, -$0.score, $0.id) < (wears[$1.outfit.baseKey] ?? 0, -$1.score, $1.id)
                    }
                if let pick {
                    for item in pick.outfit.items { wears[item.id, default: 0] += 1 }
                }
                picks[s] = (pick, pick != nil && !withinLimits.contains(pick!))
            }
        }

        let assignments = plan.slots.indices.map { s -> SlotAssignment in
            let slot = plan.slots[s]
            return SlotAssignment(
                dayIndex: slot.dayIndex, date: trip[slot.dayIndex].date, occasion: slot.occasion,
                outfit: picks[s]?.outfit ?? nil, exceedsWearLimit: picks[s]?.overLimit ?? false
            )
        }
        return PackingResult(
            items: capsule.sorted { ($0.category.rawValue, $0.id) < ($1.category.rawValue, $1.id) },
            assignments: assignments,
            outfitCount: Set(outfitsByGroup.flatMap { $0.map(\.id) }).count
        )
    }

    /// Repeating bottoms and shoes is fine, but spread the wear when there's a choice.
    private func adjusted(_ outfit: ScoredOutfit, _ wears: [String: Int]) -> Double {
        outfit.score - 2 * Double(outfit.outfit.items.map { wears[$0.id] ?? 0 }.reduce(0, +))
    }
}

/// Non-clothing basics, counted from trip length and laundry.
public enum Essentials {
    public static func checklist(days: Int, laundryEveryNDays: Int? = nil, occasions: Set<Occasion> = []) -> [(name: String, count: Int)] {
        let perCycle = min(days, laundryEveryNDays ?? days) + 1
        var list: [(String, Int)] = [("Underwear", perCycle), ("Socks", perCycle), ("Sleepwear", 1)]
        if occasions.contains(.beach) { list.append(("Swimwear", 1)) }
        if occasions.contains(.sport) { list.append(("Sports socks", min(days, 3))) }
        return list
    }
}
