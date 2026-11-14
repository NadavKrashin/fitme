import FitEngine
import Foundation
import os
import SwiftData

/// Persists reactions to suggested outfits: learned taste, saved outfits, and what was worn when.
@MainActor
struct FeedbackRecorder {
    let context: ModelContext

    /// The stored profile, or an empty one before any feedback.
    func profile() -> StyleProfile {
        storedRecord()?.profile ?? StyleProfile()
    }

    /// Likes and dislikes. Wearing goes through `wear`, which also keeps the wear history.
    func record(_ feedback: OutfitFeedback, for outfit: Outfit) {
        updateProfile { $0.record(feedback, for: outfit) }
        save()
    }

    /// Logs an outfit as worn: it teaches the engine, rests its pieces for a few days, and lands in the history.
    @discardableResult
    func wear(_ outfit: Outfit, occasion: Occasion?, on date: Date = .now) -> WearEntry {
        updateProfile { $0.record(.wore, for: outfit) }
        let pieces = records(Set(outfit.items.map(\.id)))
        let entry = WearEntry(
            outfit: outfit,
            occasion: occasion,
            wornOn: date,
            previousLastWorn: Dictionary(uniqueKeysWithValues: pieces.compactMap { record in
                record.lastWorn.map { (record.itemID, $0) }
            })
        )
        for piece in pieces {
            piece.wearCount += 1
            piece.lastWorn = date
        }
        context.insert(entry)
        save()
        return entry
    }

    /// Takes back a wear: the history entry, the learned pairing, and each piece's wear count and date.
    func unwear(_ entry: WearEntry) {
        let pieces = records(Set(entry.itemIDs))
        updateProfile { $0.revert(.wore, for: Outfit(items: pieces.map(\.item))) }
        let previous = entry.previousLastWorn
        for piece in pieces {
            piece.wearCount = max(0, piece.wearCount - 1)
            // Only roll the date back if nothing was worn since.
            if piece.lastWorn == entry.wornOn {
                piece.lastWorn = previous[piece.itemID]
            }
        }
        context.delete(entry)
        save()
    }

    /// The entry logging this outfit on the same day as `date`, if any.
    func wearEntry(for outfitID: String, on date: Date = .now, calendar: Calendar = .current) -> WearEntry? {
        let entries = (try? context
            .fetch(FetchDescriptor<WearEntry>(predicate: #Predicate { $0.outfitID == outfitID })))
        return entries?.first { calendar.isDate($0.wornOn, inSameDayAs: date) }
    }

    /// Takes back a like or dislike (wear history is left alone).
    func revert(_ feedback: OutfitFeedback, for outfit: Outfit) {
        updateProfile { $0.revert(feedback, for: outfit) }
        save()
    }

    /// Forgets every learned pairing. Saved outfits and wear history stay.
    func resetLearning() {
        for record in (try? context.fetch(FetchDescriptor<StyleProfileRecord>())) ?? [] {
            context.delete(record)
        }
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

    private func records(_ ids: Set<String>) -> [ItemRecord] {
        ((try? context.fetch(FetchDescriptor<ItemRecord>())) ?? []).filter { ids.contains($0.itemID) }
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
