import FitEngine
import Foundation
import SwiftData
import Testing
@testable import FitMe

@MainActor
struct CaptureModelTests {
    let container = try! Persistence.makeInMemoryContainer()

    private func model(
        processor: FakePhotoProcessor = .init(),
        tagger: FakeTagger = .init(),
        transport: any HTTPTransport = RecordingTransport(body: "product-image")
    ) -> CaptureModel {
        CaptureModel(processor: processor, tagger: tagger, transport: transport, context: container.mainContext)
    }

    private func drafts() throws -> [CaptureDraft] {
        try container.mainContext.fetch(FetchDescriptor<CaptureDraft>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    @Test func importedPhotosBecomeTaggedDrafts() async throws {
        let capture = model()
        await capture.importPhotos(loaders([Data([1]), Data([2]), Data([3]), Data([4])]))

        let all = try drafts()
        #expect(all.count == 4)
        #expect(all.allSatisfy { $0.status == .ready && $0.cutout != nil && $0.tags?.name == "Navy crewneck sweater" })
        #expect(all.first?.proposedItem.colors.first?.hex == "#1F2A44")
        #expect(capture.inFlight == 0)
    }

    @Test func taggingFailureKeepsThePhotoAndExplains() async throws {
        await model(tagger: FakeTagger(error: ClaudeError.missingAPIKey)).importPhotos(loaders([Data([1])]))

        let draft = try #require(try drafts().first)
        #expect(draft.status == .failed)
        #expect(draft.cutout != nil, "the cutout is kept so the item can be tagged by hand")
        #expect(draft.errorMessage == ClaudeError.missingAPIKey.userMessage)
        #expect(draft.proposedItem.category == ItemTags.blank.category)
    }

    @Test func unreadablePhotoFails() async throws {
        await model(processor: FakePhotoProcessor(fails: true)).importPhotos(loaders([Data([1])]))
        let draft = try #require(try drafts().first)
        #expect(draft.status == .failed)
        #expect(draft.cutout == nil)
    }

    @Test func confirmMovesTheDraftIntoTheCloset() async throws {
        let capture = model()
        await capture.importPhotos(loaders([Data([7])]))
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
        await capture.importPhotos(loaders([Data([1])]))
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
        await model(tagger: FakeTagger(error: ClaudeError.missingAPIKey)).importPhotos(loaders([Data([1])]))
        let draft = try #require(try drafts().first)

        await model().retry(draft)

        #expect(draft.status == .ready)
        #expect(draft.errorMessage == nil)
    }

    @Test func duplicatePhotosAreSkippedWithANote() async throws {
        let capture = model()
        await capture.importPhotos(loaders([Data([1]), Data([2]), Data([1])]))
        #expect(try drafts().count == 2)
        #expect(capture.lastImportNote == "Skipped 1 photo already added.")

        // Again later, after one became a closet item.
        let draft = try #require(try drafts().first)
        capture.confirm(draft, as: draft.proposedItem)
        await capture.importPhotos(loaders([Data([1]), Data([2]), Data([3])]))
        #expect(try drafts().count == 2)
        #expect(capture.lastImportNote == "Skipped 2 photos already added.")
    }

    @Test func unreadablePhotosAreCountedNotDrafted() async throws {
        let capture = model()
        await capture.importPhotos(loaders([nil, Data([5])]))
        #expect(try drafts().count == 1)
        #expect(capture.lastImportNote == "Couldn't load 1 photo.")
        #expect(capture.importing == 0)
    }

    @Test func itemBoxCropsTheCutout() async throws {
        let box = ItemBox(x0: 100, y0: 200, x1: 600, y1: 900)
        await model(tagger: FakeTagger(itemBox: box)).importPhotos(loaders([Data([3])]))
        let draft = try #require(try drafts().first)
        #expect(draft.cutout == Data("cropped".utf8) + Data("cutout".utf8) + Data([3]))
    }

    @Test func noBoxKeepsTheUncroppedCutout() async throws {
        await model().importPhotos(loaders([Data([3])]))
        #expect(try drafts().first?.cutout == Data("cutout".utf8) + Data([3]))
    }

    // MARK: Product photos

    private static let productPage: ProductPage = {
        let snapshot = PageSnapshot(
            url: "https://shop.example.com/p/tee",
            title: "Tee",
            jsonLD: [
                #"{"@type":"Product","name":"Broken-in tee","brand":"J.Crew","image":"https://cdn.example.com/tee.jpg"}"#,
            ],
            meta: [:],
            images: []
        )
        // The snapshot above has a photo, so it always parses.
        return ProductPage(snapshot: snapshot)!
    }()

    private func importedDraft(with capture: CaptureModel) async throws -> CaptureDraft {
        await capture.importPhotos(loaders([Data([9])]))
        return try #require(try drafts().first)
    }

    @Test func aProductPhotoReplacesThePhotoAndTagsButKeepsTheOriginal() async throws {
        let transport = RecordingTransport(body: "product-image")
        let capture = model(transport: transport)
        let draft = try await importedDraft(with: capture)
        let page = Self.productPage

        try await capture.useProductPhoto(at: page.imageURLs[0], from: page, for: draft)

        #expect(await transport.requests.map(\.url) == [page.imageURLs[0]])
        #expect(draft.cutout == Data("cutout".utf8) + Data("product-image".utf8))
        #expect(draft.photo == Data("photo".utf8) + Data("product-image".utf8))
        #expect(draft.originalImage == Data([9]))
        #expect(draft.tags?.name == "Tagged from the listing")
        #expect(draft.status == .ready)
        #expect(draft.brand == "J.Crew")
        #expect(draft.productURL == page.url)
        #expect(capture.inFlight == 0)

        capture.confirm(draft, as: draft.proposedItem)
        let record = try #require(try container.mainContext.fetch(FetchDescriptor<ItemRecord>()).first)
        #expect(record.brand == "J.Crew")
        #expect(record.productURL == page.url)
    }

    @Test func aFailedDownloadLeavesTheDraftAsItWas() async throws {
        let capture = model(transport: RecordingTransport(status: 403, body: "blocked"))
        let draft = try await importedDraft(with: capture)
        let page = Self.productPage

        await #expect(throws: ProductImportError.downloadFailed) {
            try await capture.useProductPhoto(at: page.imageURLs[0], from: page, for: draft)
        }

        #expect(draft.cutout == Data("cutout".utf8) + Data([9]))
        #expect(draft.tags?.name == "Navy crewneck sweater")
        #expect(draft.brand == nil)
        #expect(draft.productURL == nil)
        #expect(capture.inFlight == 0)
    }

    @Test func anUnreadableProductPhotoLeavesTheDraftAsItWas() async throws {
        let draft = try await importedDraft(with: model())
        let page = Self.productPage

        await #expect(throws: ProductImportError.unreadablePhoto) {
            try await model(processor: FakePhotoProcessor(fails: true))
                .useProductPhoto(at: page.imageURLs[0], from: page, for: draft)
        }
        #expect(draft.cutout == Data("cutout".utf8) + Data([9]))
        #expect(draft.productURL == nil)
    }

    @Test func whenRetaggingFailsTheProductPhotoIsKeptWithTheOldTags() async throws {
        let draft = try await importedDraft(with: model())
        let page = Self.productPage

        try await model(tagger: FakeTagger(error: ClaudeError.missingAPIKey))
            .useProductPhoto(at: page.imageURLs[0], from: page, for: draft)

        #expect(draft.cutout == Data("cutout".utf8) + Data("product-image".utf8))
        #expect(draft.tags?.name == "Navy crewneck sweater")
        #expect(draft.status == .ready)
        #expect(draft.errorMessage == ClaudeError.missingAPIKey.userMessage)
    }

    @Test func withNoTagsAtAllTheProductNameIsUsed() async throws {
        let untaggable = FakeTagger(error: ClaudeError.missingAPIKey)
        let capture = model(tagger: untaggable)
        let draft = try await importedDraft(with: capture)
        let page = Self.productPage

        try await capture.useProductPhoto(at: page.imageURLs[0], from: page, for: draft)

        #expect(draft.proposedItem.name == "Broken-in tee")
        #expect(draft.status == .failed)
    }
}
