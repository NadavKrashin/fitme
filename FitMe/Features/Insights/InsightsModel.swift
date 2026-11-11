import FitEngine
import Foundation
import Observation

/// What the closet can and can't do: hard-to-style pieces, the best next buy, workhorses, pieces resting in the
/// closet, and the taste FitMe has learned.
@MainActor
@Observable
final class InsightsModel {
    enum State: Equatable {
        case idle
        case analyzing
        case analyzed(ClosetInsights)
    }

    /// A piece counts as resting once it hasn't been worn for this long.
    static let restingAfterDays = 60
    /// New pieces get this long before "never worn" is worth mentioning.
    static let settlingInDays = 14

    private(set) var state: State = .idle
    private let analyzer: ClosetAnalyzer

    init(analyzer: ClosetAnalyzer) {
        self.analyzer = analyzer
    }

    func analyze(_ closet: [Item]) async {
        state = .analyzing
        state = await .analyzed(Self.analyze(closet, with: analyzer))
    }

    /// Runs off the main actor: it searches every piece in every kind of day, about a second for a big closet.
    @concurrent
    private nonisolated static func analyze(_ closet: [Item], with analyzer: ClosetAnalyzer) async -> ClosetInsights {
        analyzer.analyze(closet)
    }

    /// Pieces never worn since they settled in, then pieces not worn for a while, longest first.
    static func resting(_ records: [ItemRecord], now: Date = .now, calendar: Calendar = .current) -> [ItemRecord] {
        let daysSince = { (date: Date) in calendar.dateComponents([.day], from: date, to: now).day ?? 0 }
        let neverWorn = records
            .filter { $0.lastWorn == nil && daysSince($0.addedAt) >= settlingInDays }
            .sorted { ($0.addedAt, $0.itemID) < ($1.addedAt, $1.itemID) }
        let notLately = records
            .compactMap { record in record.lastWorn.map { (record, $0) } }
            .filter { daysSince($0.1) >= restingAfterDays }
            .sorted { ($0.1, $0.0.itemID) < ($1.1, $1.0.itemID) }
            .map(\.0)
        return neverWorn + notLately
    }
}
