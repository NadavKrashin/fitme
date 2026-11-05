#if STAGING
import FitEngine
import Foundation
import os
import SwiftData
import SwiftUI

/// A ready-made closet for trying the app without photographing anything. Staging and Debug builds only.
enum DemoCloset {
    enum LoadError: Error {
        case resourceMissing
    }

    static func items(bundle: Bundle = .main) throws -> [Item] {
        guard let url = bundle.url(forResource: "DemoCloset", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        return try JSONDecoder().decode([Item].self, from: Data(contentsOf: url))
    }

    /// Replaces whatever is in the closet with the demo items.
    @MainActor
    static func load(into context: ModelContext) throws {
        try removeAllItems(from: context)
        for item in try items() {
            context.insert(ItemRecord(item: item))
        }
        try context.save()
    }

    @MainActor
    static func clear(_ context: ModelContext) throws {
        try removeAllItems(from: context)
        try context.save()
    }

    /// Deletes record by record: `delete(model:)` is a store-level batch delete that misses unsaved inserts.
    @MainActor
    private static func removeAllItems(from context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<ItemRecord>()) {
            context.delete(record)
        }
    }
}

struct DemoClosetSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button("Load demo closet") { run("load", DemoCloset.load) }
            Button("Clear closet", role: .destructive) { run("clear", DemoCloset.clear) }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        } header: {
            Text("Demo data")
        } footer: {
            Text("Staging only. Loading replaces everything in this app's closet.")
        }
    }

    private func run(_ action: String, _ operation: (ModelContext) throws -> Void) {
        do {
            try operation(modelContext)
            errorMessage = nil
        } catch {
            Logger.demoData.error("Couldn't \(action) demo closet: \(String(describing: error))")
            errorMessage = "Couldn't \(action) the demo closet."
        }
    }
}
#endif
