import FitEngine
import Foundation
import SwiftData
import Testing
@testable import FitMe

@MainActor
struct CaptureModelTests {
    let container = try! Persistence.makeInMemoryContainer()

    private func model(processor: FakePhotoProcessor = .init(), tagger: FakeTagger = .init()) -> CaptureModel {
        CaptureModel(processor: processor, tagger: tagger, context: container.mainContext)
    }

    private func drafts() throws -> [CaptureDraft] {
        try container.mainContext.fetch(FetchDescriptor<CaptureDraft>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    @Test func importedPhotosBecomeTaggedDrafts() async throws {
        let capture = model()
        await capture.importPhotos([Data([1]), Data([2]), Data([3]), Data([4])])

        let all = try drafts()
        #expect(all.count == 4)
        #expect(all.allSatisfy { $0.status == .ready && $0.cutout != nil && $0.tags?.name == "Navy crewneck sweater" })
        #expect(all.first?.proposedItem.colors.first?.hex == "#1F2A44")
        #expect(capture.inFlight == 0)
    }

    @Test func taggingFailureKeepsThePhotoAndExplains() async throws {
        await model(tagger: FakeTagger(error: ClaudeError.missingAPIKey)).importPhotos([Data([1])])

        let draft = try #require(try drafts().first)
        #expect(draft.status == .failed)
        #expect(draft.cutout != nil, "the cutout is kept so the item can be tagged by hand")
        #expect(draft.errorMessage == ClaudeError.missingAPIKey.userMessage)
        #expect(draft.proposedItem.category == ItemTags.blank.category)
    }

    @Test func unreadablePhotoFails() async throws {
        await model(processor: FakePhotoProcessor(fails: true)).importPhotos([Data([1])])
        let draft = try #require(try drafts().first)
        #expect(draft.status == .failed)
        #expect(draft.cutout == nil)
    }

    @Test func confirmMovesTheDraftIntoTheCloset() async throws {
        let capture = model()
        await capture.importPhotos([Data([7])])
        let draft = try #require(try drafts().first)
        var item = draft.proposedItem
        item.name = "Edited name"

        capture.confirm(draft, as: item)

        #expect(try drafts().isEmpty)
        let record = try #require(try container.mainContext.fetch(FetchDescriptor<ItemRecord>()).first)
        #expect(record.name == "Edited name")
        #expect(record.cutout == Data("cutout".utf8) + Data([7]))
        #expect(record.photo == Data("photo".utf8) + Data([7]))
    }

    @Test func discardRemovesTheDraft() async throws {
        let capture = model()
        await capture.importPhotos([Data([1])])
        try capture.discard(#require(try drafts().first))
        #expect(try drafts().isEmpty)
    }

    @Test func resumesDraftsLeftProcessing() async throws {
        container.mainContext.insert(CaptureDraft(originalImage: Data([9])))
        try container.mainContext.save()

        await model().resumePending()

        #expect(try drafts().first?.status == .ready)
    }

    @Test func retryRecoversAFailedDraft() async throws {
        await model(tagger: FakeTagger(error: ClaudeError.missingAPIKey)).importPhotos([Data([1])])
        let draft = try #require(try drafts().first)

        await model().retry(draft)

        #expect(draft.status == .ready)
        #expect(draft.errorMessage == nil)
    }
}
