import FitEngine
import Foundation
import os
import SwiftData

/// Persists reactions to suggested outfits: learned pair affinities, saved outfits, and wear history.
@MainActor
struct FeedbackRecorder {
    let context: ModelContext

    /// The stored profile, or an empty one before any feedback.
    func profile() -> StyleProfile {
        storedRecord()?.profile ?? StyleProfile()
    }

    func record(_ feedback: OutfitFeedback, for outfit: Outfit, on date: Date = .now) {
        updateProfile { $0.record(feedback, for: outfit) }
        if feedback == .wore {
            let ids = Set(outfit.items.map(\.id))
            let worn = (try? context.fetch(FetchDescriptor<ItemRecord>()))?.filter { ids.contains($0.itemID) } ?? []
            for item in worn {
                item.wearCount += 1
                item.lastWorn = date
            }
        }
        save()
    }

    /// Takes back a like or dislike (wear history is left alone).
    func revert(_ feedback: OutfitFeedback, for outfit: Outfit) {
        updateProfile { $0.revert(feedback, for: outfit) }
        save()
    }

    func saveOutfit(_ outfit: Outfit, occasion: Occasion) {
        guard savedOutfit(id: outfit.id) == nil else { return }
        context.insert(SavedOutfit(outfit: outfit, occasion: occasion))
        save()
    }

    func removeSavedOutfit(id: String) {
        guard let saved = savedOutfit(id: id) else { return }
        context.delete(saved)
        save()
    }

    private func savedOutfit(id: String) -> SavedOutfit? {
        try? context.fetch(FetchDescriptor<SavedOutfit>(predicate: #Predicate { $0.outfitID == id })).first
    }

    private func updateProfile(_ change: (inout StyleProfile) -> Void) {
        let record = storedRecord() ?? {
            let new = StyleProfileRecord()
            context.insert(new)
            return new
        }()
        var profile = record.profile
        change(&profile)
        record.profile = profile
    }

    private func storedRecord() -> StyleProfileRecord? {
        try? context.fetch(FetchDescriptor<StyleProfileRecord>()).first
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Logger.today.error("Couldn't save feedback: \(String(describing: error))")
        }
    }
}
