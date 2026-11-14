import FitEngine
import Foundation
import SwiftData

/// A photo on its way into the closet: processed and tagged in the background, then reviewed by the user.
/// Drafts never appear in the closet or in outfit suggestions until confirmed.
@Model
final class CaptureDraft {
    enum Status: String, Codable {
        /// Waiting for, or in, image processing and tagging.
        case processing
        /// Ready for review, with tags filled in.
        case ready
        /// Processing or tagging failed. Still reviewable; tags start blank.
        case failed
    }

    @Attribute(.unique) var draftID: String
    var status: Status
    var errorMessage: String?
    var createdAt: Date
    @Attribute(.externalStorage) var originalImage: Data
    @Attribute(.externalStorage) var photo: Data?
    @Attribute(.externalStorage) var cutout: Data?
    var colors: [StoredColor]
    var tags: ItemTags?
    /// SHA-256 of the original image, to skip photos that were already added.
    var fingerprint: String?
    /// Set when the photo and tags came from the item's product page instead of the owner's photo.
    var brand: String?
    var productURL: URL?

    init(originalImage: Data, fingerprint: String? = nil, createdAt: Date = .now) {
        draftID = UUID().uuidString
        status = .processing
        self.originalImage = originalImage
        self.fingerprint = fingerprint
        self.createdAt = createdAt
        colors = []
    }

    /// Everything a product photo replaces, so it can be put back.
    struct Snapshot {
        let photo: Data?
        let cutout: Data?
        let colors: [StoredColor]
        let tags: ItemTags?
        let status: Status
        let errorMessage: String?
        let brand: String?
        let productURL: URL?
    }

    var snapshot: Snapshot {
        Snapshot(
            photo: photo,
            cutout: cutout,
            colors: colors,
            tags: tags,
            status: status,
            errorMessage: errorMessage,
            brand: brand,
            productURL: productURL
        )
    }

    func restore(_ snapshot: Snapshot) {
        photo = snapshot.photo
        cutout = snapshot.cutout
        colors = snapshot.colors
        tags = snapshot.tags
        status = snapshot.status
        errorMessage = snapshot.errorMessage
        brand = snapshot.brand
        productURL = snapshot.productURL
    }

    /// The item this draft would become, from whatever has been tagged so far.
    var proposedItem: Item {
        (tags ?? .blank).item(
            id: draftID,
            colors: colors.map { ItemColor(hex: $0.hex, proportion: $0.proportion) }
        )
    }
}
