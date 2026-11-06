import FitEngine
import SwiftData
import SwiftUI

/// View and edit a closet item. Changes are saved when leaving the screen.
struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let record: ItemRecord
    @State private var item: Item
    @State private var isConfirmingDelete = false
    @State private var isDeleted = false

    init(record: ItemRecord) {
        self.record = record
        _item = State(initialValue: record.item)
    }

    var body: some View {
        Form {
            Section {
                ItemThumbnail(item: item, image: record.cutout, size: 220)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            ItemEditorSections(item: $item)

            Section {
                Toggle("Available (not in the laundry)", isOn: $item.isAvailable)
                Button("Delete item", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(item.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                isDeleted = true
                modelContext.delete(record)
                dismiss()
            }
        }
        .onDisappear {
            // `Item ==` compares ids only, so save unconditionally rather than diffing.
            if !isDeleted {
                record.update(from: item)
            }
        }
    }
}
