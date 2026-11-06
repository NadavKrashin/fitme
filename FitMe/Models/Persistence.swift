import Foundation
import SwiftData

enum Persistence {
    static let models: [any PersistentModel.Type] = [
        ItemRecord.self,
        CaptureDraft.self,
        StyleProfileRecord.self,
        SavedOutfit.self,
    ]

    /// The on-device closet store. Creates Application Support first: on a fresh install it doesn't exist yet,
    /// and Core Data logs a burst of errors while working around that.
    static func makeContainer() throws -> ModelContainer {
        let directory = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: directory.appending(path: "FitMe.store"))
        return try ModelContainer(for: Schema(models), configurations: configuration)
    }

    /// For tests and previews.
    static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
