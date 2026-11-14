import FitEngine
import SwiftData
import SwiftUI

/// View and edit a closet item. Changes are saved when leaving the screen.
struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CaptureModel.self) private var capture
    let record: ItemRecord
    @State private var item: Item
    @State private var isConfirmingDelete = false
    @State private var isDeleted = false
    @State private var isFindingOnline = false
    @State private var toast: Toast?

    init(record: ItemRecord) {
        self.record = record
        _item = State(initialValue: record.item)
    }

    var body: some View {
        Form {
            Section { header }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            // Its own row: a list gives a row's taps to the navigation link in it, so a button beside
            // "Outfits with this" never fires.
            Section { productMatch }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            ItemEditorSections(item: $item)

            Section {
                Toggle("Available (not in the laundry)", isOn: $item.isAvailable)
                    .tint(Theme.terracotta)
                Button("Delete item", role: .destructive) { isConfirmingDelete = true }
            }
            .editorialRow()
        }
        .editorialCanvas()
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(item.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                isDeleted = true
                modelContext.delete(record)
                dismiss()
            }
        }
        .toast(toast) { toast = nil }
        .sheet(isPresented: $isFindingOnline) {
            FindOnlineView(brand: record.brand, itemDescription: item.name, apply: useProductPhoto)
        }
        .onDisappear {
            // `Item ==` compares ids only, so save unconditionally rather than diffing.
            if !isDeleted {
                record.update(from: item)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            ItemThumbnail(item: item, image: record.cutout, size: 240, isFramed: record.cutout == nil)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.card, in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
            NavigationLink {
                OutfitsWithItemView(item: item)
            } label: {
                Label("Outfits with this", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.accent))
        }
    }

    private var productMatch: some View {
        ProductMatchCard(brand: record.brand, productURL: record.productURL) {
            // Keep edits made so far; the product's tags replace them only if the owner goes through with it.
            record.update(from: item)
            isFindingOnline = true
        }
    }

    private func useProductPhoto(_ photo: URL, from page: ProductPage) async throws {
        let change = try await capture.useProductPhoto(at: photo, from: page, for: record)
        item = record.item
        toast = .productPhoto(from: page, isRetagged: change.taggingMessage == nil) {
            capture.restore(record, to: change.previous)
            item = record.item
        }
    }
}
