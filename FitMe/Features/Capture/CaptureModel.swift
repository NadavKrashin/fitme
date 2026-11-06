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

    private let processor: any PhotoProcessing
    private let tagger: any TaggingService
    private let context: ModelContext

    init(processor: any PhotoProcessing, tagger: any TaggingService, context: ModelContext) {
        self.processor = processor
        self.tagger = tagger
        self.context = context
    }

    /// Creates a draft per photo right away (so nothing is lost if the app quits), then processes them.
    func importPhotos(_ images: [Data]) async {
        let drafts = images.map { CaptureDraft(originalImage: $0) }
        drafts.forEach(context.insert)
        save()
        await process(drafts)
    }

    /// Picks up drafts left mid-processing by a previous session.
    func resumePending() async {
        let processing = CaptureDraft.Status.processing
        let pending = (try? context.fetch(FetchDescriptor<CaptureDraft>(
            predicate: #Predicate { $0.status == processing },
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
        await process(pending)
    }

    func retry(_ draft: CaptureDraft) async {
        draft.status = .processing
        draft.errorMessage = nil
        save()
        await process([draft])
    }

    /// Adds the reviewed item to the closet and removes the draft.
    func confirm(_ draft: CaptureDraft, as item: Item) {
        context.insert(ItemRecord(item: item, photo: draft.photo, cutout: draft.cutout))
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
        let photo: ProcessedPhoto
        do {
            photo = try await processor.process(job.image)
        } catch {
            return Outcome(draftID: job.draftID, photo: nil, tags: nil, errorMessage: "Couldn't read this photo.")
        }
        do {
            let tags = try await tagger.tags(forJPEG: photo.taggingJPEG)
            return Outcome(draftID: job.draftID, photo: photo, tags: tags, errorMessage: nil)
        } catch {
            return Outcome(draftID: job.draftID, photo: photo, tags: nil, errorMessage: message(for: error))
        }
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

    private func save() {
        do {
            try context.save()
        } catch {
            Logger.capture.error("Couldn't save capture drafts: \(String(describing: error))")
        }
    }
}
