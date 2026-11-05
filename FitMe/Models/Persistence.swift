import Foundation
import SwiftData

enum Persistence {
    /// The on-device closet store. Creates Application Support first: on a fresh install it doesn't exist yet,
    /// and Core Data logs a burst of errors while working around that.
    static func makeContainer() throws -> ModelContainer {
        let directory = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: directory.appending(path: "FitMe.store"))
        return try ModelContainer(for: ItemRecord.self, configurations: configuration)
    }
}
