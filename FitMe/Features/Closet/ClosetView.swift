import FitEngine
import os
import PhotosUI
import SwiftData
import SwiftUI

struct ClosetView: View {
    @Environment(CaptureModel.self) private var capture
    @Query(sort: \ItemRecord.name) private var records: [ItemRecord]
    @Query private var drafts: [CaptureDraft]
    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var isShowingInbox = false
    @State private var categoryFilter: ItemCategory?
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !drafts.isEmpty {
                        inboxBanner
                    }
                    if records.isEmpty {
                        ContentUnavailableView(
                            "Your closet is empty",
                            systemImage: "hanger",
                            description: Text(emptyHint)
                        )
                    } else {
                        categoryChips
                        ForEach(sections, id: \.category) { section in
                            categorySection(section.category, records: section.records)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Closet")
            .navigationDestination(for: String.self) { id in
                if let record = records.first(where: { $0.itemID == id }) {
                    ItemDetailView(record: record)
                }
            }
            .searchable(text: $searchText, prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(selection: $pickerSelection, matching: .images) {
                        Label("Add photos", systemImage: "plus")
                    }
                }
            }
            .onChange(of: pickerSelection) { _, selection in
                guard !selection.isEmpty else { return }
                pickerSelection = []
                isShowingInbox = true
                Task { await importPhotos(selection) }
            }
            .sheet(isPresented: $isShowingInbox) { InboxView() }
        }
    }

    // MARK: Sections

    private var inboxBanner: some View {
        let processing = drafts.count(where: { $0.status == .processing })
        let toReview = drafts.count - processing
        let summary = [
            toReview > 0 ? "\(toReview) to review" : nil,
            processing > 0 ? "\(processing) processing" : nil,
        ].compactMap(\.self).joined(separator: " · ")
        return Button { isShowingInbox = true } label: {
            HStack {
                Image(systemName: "tray.full")
                VStack(alignment: .leading) {
                    Text("Inbox").font(.headline)
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var categoryChips: some View {
        let present = Set(records.map(\.category))
        let categories = ItemCategory.allCases.filter(present.contains)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ChipButton(title: "All", isOn: categoryFilter == nil) { categoryFilter = nil }
                ForEach(categories, id: \.self) { category in
                    ChipButton(title: category.title, isOn: categoryFilter == category) { categoryFilter = category }
                }
            }
        }
    }

    private var sections: [(category: ItemCategory, records: [ItemRecord])] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let visible = records.filter { record in
            (categoryFilter == nil || record.category == categoryFilter)
                && (query.isEmpty || record.name.localizedCaseInsensitiveContains(query))
        }
        return Dictionary(grouping: visible, by: \.category)
            .sorted { $0.key.layerOrder < $1.key.layerOrder }
            .map { ($0.key, $0.value) }
    }

    private var emptyHint: String {
        switch AppEnvironment.current {
        case .staging: "Tap + to add photos of your clothes, or load the demo closet from Settings."
        case .production: "Tap + to add photos of your clothes. Photograph them one by one in the Camera app first."
        }
    }

    private func categorySection(_ category: ItemCategory, records: [ItemRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(category.title) · \(records.count)")
                .font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(records) { record in
                    NavigationLink(value: record.itemID) {
                        VStack(spacing: 4) {
                            ItemThumbnail(item: record.item, image: record.cutout, size: 72)
                            Text(record.name)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Import

    private func importPhotos(_ selection: [PhotosPickerItem]) async {
        var images: [Data] = []
        for item in selection {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    images.append(data)
                }
            } catch {
                Logger.capture.error("Couldn't load a picked photo: \(String(describing: error))")
            }
        }
        await capture.importPhotos(images)
    }
}

#if DEBUG
#Preview {
    ClosetView()
        .environment(\.dependencies, .preview())
        .environment(PreviewData.captureModel)
        .modelContainer(PreviewData.container)
}
#endif
