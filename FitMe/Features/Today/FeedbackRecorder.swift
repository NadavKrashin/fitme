import FitEngine
import Foundation
import os
import SwiftData

/// Persists reactions to suggested outfits: learned pair affinities, and wear history for "wore it".
@MainActor
struct FeedbackRecorder {
    let context: ModelContext

    /// The stored profile, or an empty one before any feedback.
    func profile() -> StyleProfile {
        storedRecord()?.profile ?? StyleProfile()
    }

    func record(_ feedback: OutfitFeedback, for outfit: Outfit, on date: Date = .now) {
        let record = storedRecord() ?? {
            let new = StyleProfileRecord()
            context.insert(new)
            return new
        }()
        var profile = record.profile
        profile.record(feedback, for: outfit)
        record.profile = profile

        if feedback == .wore {
            let ids = Set(outfit.items.map(\.id))
            let worn = (try? context.fetch(FetchDescriptor<ItemRecord>()))?.filter { ids.contains($0.itemID) } ?? []
            for item in worn {
                item.wearCount += 1
                item.lastWorn = date
            }
        }

        do {
            try context.save()
        } catch {
            Logger.today.error("Couldn't save feedback: \(String(describing: error))")
        }
    }

    private func storedRecord() -> StyleProfileRecord? {
        try? context.fetch(FetchDescriptor<StyleProfileRecord>()).first
    }
}
