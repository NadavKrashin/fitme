import CryptoKit
import FitEngine
import Foundation
import Observation
import os
import SwiftData

/// Turns imported photos into reviewed closet items: photo → draft → processed and tagged → confirmed.
///
/// Lives for the whole app session so processing continues while the user browses elsewhere.
@MainActor
@Observable
final class CaptureModel {
    /// Photos processed at once: enough to hide network latency, few enough to stay within memory and rate limits.
    private static let concurrency = 3

    private(set) var inFlight = 0
    /// Photos picked but not loaded yet: shown so the inbox never looks empty right after adding.
    private(set) var importing = 0
    /// What the last import skipped, if anything (duplicates, unreadable photos).
    private(set) var lastImportNote: String?

    private let processor: any PhotoProcessing
    private let tagger: any TaggingService
    private let context: ModelContext

    init(processor: any PhotoProcessing, tagger: any TaggingService, context: ModelContext) {
        self.processor = processor
        self.tagger = tagger
        self.context = context
    }

    /// Each loader fetches one photo (e.g. from the photo library). A draft is saved as soon as its photo loads,
    /// so nothing is lost if the app quits; photos already in the inbox or closet are skipped.
    func importPhotos(_ loaders: [@Sendable () async -> Data?]) async {
        importing += loaders.count
        lastImportNote = nil
        var known = knownFingerprints()
        var drafts: [CaptureDraft] = []
        var duplicates = 0
        var unreadable = 0

        for load in loaders {
            let image = await load()
            importing -= 1
            guard let image else {
                unreadable += 1
                continue
            }
            let fingerprint = Self.fingerprint(of: image)
            guard known.insert(fingerprint).inserted else {
                duplicates += 1
                continue
            }
            let draft = CaptureDraft(originalImage: image, fingerprint: fingerprint)
            context.insert(draft)
            save()
            drafts.append(draft)
        }

        lastImportNote = Self.note(duplicates: duplicates, unreadable: unreadable)
        await process(drafts)
    }

    /// Picks up drafts left mid-processing by a previous session.
    func resumePending() async {
        // Filtered in Swift: a #Predicate on the Codable `status` enum silently matches nothing in SwiftData.
        // There are only ever a handful of drafts.
        let drafts = (try? context.fetch(FetchDescriptor<CaptureDraft>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        await process(drafts.filter { $0.status == .processing })
    }

    func retry(_ draft: CaptureDraft) async {
        draft.status = .processing
        draft.errorMessage = nil
        save()
        await process([draft])
    }

    /// Adds the reviewed item to the closet and removes the draft.
    func confirm(_ draft: CaptureDraft, as item: Item) {
        let record = ItemRecord(item: item, photo: draft.photo, cutout: draft.cutout)
        record.sourceFingerprint = draft.fingerprint
        context.insert(record)
        context.delete(draft)
        save()
    }

    func discard(_ draft: CaptureDraft) {
        context.delete(draft)
        save()
    }

    // MARK: Processing

    private struct Job: Sendable {
        let draftID: String
        let image: Data
    }

    private struct Outcome: Sendable {
        let draftID: String
        let photo: ProcessedPhoto?
        let tags: ItemTags?
        let errorMessage: String?
    }

    private func process(_ drafts: [CaptureDraft]) async {
        let jobs = drafts.map { Job(draftID: $0.draftID, image: $0.originalImage) }
        guard !jobs.isEmpty else { return }
        inFlight += jobs.count
        defer { inFlight -= jobs.count }

        let processor = processor
        let tagger = tagger
        await withTaskGroup(of: Outcome.self) { group in
            var pending = jobs[...]
            for _ in 0 ..< Self.concurrency {
                guard let job = pending.popFirst() else { break }
                group.addTask { await Self.run(job, processor: processor, tagger: tagger) }
            }
            for await outcome in group {
                apply(outcome)
                if let job = pending.popFirst() {
                    group.addTask { await Self.run(job, processor: processor, tagger: tagger) }
                }
            }
        }
    }

    private nonisolated static func run(
        _ job: Job,
        processor: any PhotoProcessing,
        tagger: any TaggingService
    ) async -> Outcome {
        var photo: ProcessedPhoto
        do {
            photo = try await processor.process(job.image)
        } catch {
            return Outcome(draftID: job.draftID, photo: nil, tags: nil, errorMessage: "Couldn't read this photo.")
        }
        let tagged: TaggedPhoto
        do {
            tagged = try await tagger.tag(jpeg: photo.taggingJPEG)
        } catch {
            return Outcome(draftID: job.draftID, photo: photo, tags: nil, errorMessage: message(for: error))
        }
        if let box = tagged.itemBox, let cropped = try? await processor.crop(photo, to: box) {
            photo = cropped
        }
        return Outcome(draftID: job.draftID, photo: photo, tags: tagged.tags, errorMessage: nil)
    }

    private func apply(_ outcome: Outcome) {
        let id = outcome.draftID
        guard let draft = try? context.fetch(FetchDescriptor<CaptureDraft>(predicate: #Predicate { $0.draftID == id }))
            .first
        else { return } // discarded while processing
        if let photo = outcome.photo {
            draft.photo = photo.photoJPEG
            draft.cutout = photo.cutoutPNG
            draft.colors = photo.colors.map(StoredColor.init)
        }
        draft.tags = outcome.tags
        draft.errorMessage = outcome.errorMessage
        draft.status = outcome.errorMessage == nil ? .ready : .failed
        save()
    }

    private nonisolated static func message(for error: Error) -> String {
        switch error {
        case let error as ClaudeError: error.userMessage
        case TaggingError.invalidTags: "Claude returned an unusable answer. Try again or tag it by hand."
        default: "Tagging failed. Try again or tag it by hand."
        }
    }

    // MARK: Duplicates

    static func fingerprint(of image: Data) -> String {
        SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
    }

    private func knownFingerprints() -> Set<String> {
        let drafts = (try? context.fetch(FetchDescriptor<CaptureDraft>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<ItemRecord>())) ?? []
        return Set(drafts.compactMap(\.fingerprint) + records.compactMap(\.sourceFingerprint))
    }

    static func note(duplicates: Int, unreadable: Int) -> String? {
        let parts = [
            duplicates > 0 ? "Skipped \(duplicates) photo\(duplicates == 1 ? "" : "s") already added." : nil,
            unreadable > 0 ? "Couldn't load \(unreadable) photo\(unreadable == 1 ? "" : "s")." : nil,
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Logger.capture.error("Couldn't save capture drafts: \(String(describing: error))")
        }
    }
}
