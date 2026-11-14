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

    /// The item's product-photo cutout (`demo-<id>.png`), when bundled.
    static func cutout(for itemID: String, bundle: Bundle = .main) -> Data? {
        bundle.url(forResource: "demo-\(itemID)", withExtension: "png").flatMap { try? Data(contentsOf: $0) }
    }

    /// Replaces whatever is in the closet with the demo items and their photos, with a made-up wear history.
    @MainActor
    static func load(into context: ModelContext, now: Date = .now) throws {
        try removeAllItems(from: context)
        for (index, item) in try items().enumerated() {
            let record = ItemRecord(
                item: item,
                cutout: cutout(for: item.id),
                addedAt: now.addingTimeInterval(-addedAgo)
            )
            (record.wearCount, record.lastWorn) = wearHistory(index, now: now)
            context.insert(record)
        }
        try context.save()
    }

    /// The demo closet pretends to be four months old, so insights about wear have something to show.
    private static let addedAgo: TimeInterval = 120 * 86400

    /// Every seventh piece never worn; the rest worn a few times, last between a week and about four months ago.
    private static func wearHistory(_ index: Int, now: Date) -> (count: Int, lastWorn: Date?) {
        guard index % 7 != 3 else { return (0, nil) }
        let daysAgo = 7 + (index * 37) % 110
        return (1 + index % 6, now.addingTimeInterval(-Double(daysAgo) * 86400))
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
            Button("Load demo closet") { run("load") { try DemoCloset.load(into: $0) } }
            Button("Clear closet", role: .destructive) { run("clear", DemoCloset.clear) }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.terracotta)
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
