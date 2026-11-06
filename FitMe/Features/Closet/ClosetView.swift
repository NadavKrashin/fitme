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

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 14, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !drafts.isEmpty || capture.importing > 0 {
                        inboxBanner
                    }
                    if records.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "hanger")
                                .font(.title)
                                .foregroundStyle(Theme.terracotta)
                            Text("Start your closet")
                                .font(Theme.title(20))
                                .foregroundStyle(Theme.ink)
                            Text(emptyHint)
                                .font(.callout)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .card(padding: 22)
                    } else {
                        categoryChips
                        ForEach(sections, id: \.category) { section in
                            categorySection(section.category, records: section.records)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 40)
            }
            .navigationTitle("Closet")
            .editorialCanvas()
            .navigationDestination(for: String.self) { id in
                if let record = records.first(where: { $0.itemID == id }) {
                    ItemDetailView(record: record)
                }
            }
            .searchable(text: $searchText, prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(selection: $pickerSelection, matching: .images) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.onTerracotta)
                            .frame(width: 34, height: 34)
                            .background(Theme.terracotta, in: .circle)
                    }
                    .accessibilityLabel("Add photos")
                }
            }
            .onChange(of: pickerSelection) { _, selection in
                guard !selection.isEmpty else { return }
                pickerSelection = []
                isShowingInbox = true
                Task { await capture.importPhotos(selection.map(Self.loader)) }
            }
            .sheet(isPresented: $isShowingInbox) { InboxView() }
        }
    }

    // MARK: Sections

    private var inboxBanner: some View {
        let processing = drafts.count(where: { $0.status == .processing })
        let toReview = drafts.count - processing
        let summary = [
            capture.importing > 0 ? "importing \(capture.importing)" : nil,
            toReview > 0 ? "\(toReview) to review" : nil,
            processing > 0 ? "\(processing) processing" : nil,
        ].compactMap(\.self).joined(separator: " · ")
        return Button { isShowingInbox = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "tray.full")
                    .font(.title3)
                    .foregroundStyle(Theme.onTerracotta)
                    .frame(width: 44, height: 44)
                    .background(Theme.terracotta, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inbox").font(Theme.title(17)).foregroundStyle(Theme.ink)
                    Text(summary).font(.footnote).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkMuted)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var categoryChips: some View {
        let present = Set(records.map(\.category))
        let categories = ItemCategory.allCases.filter(present.contains)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipButton(title: "All", isOn: categoryFilter == nil) { categoryFilter = nil }
                ForEach(categories, id: \.self) { category in
                    ChipButton(title: category.title, isOn: categoryFilter == category) { categoryFilter = category }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .padding(.horizontal, -Theme.gutter)
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
        case .staging:
            "Tap + to add photos of your clothes, or load the demo closet from Settings. \(InboxView.photoTip)"
        case .production: "Tap + to add photos of your clothes. \(InboxView.photoTip)"
        }
    }

    private func categorySection(_ category: ItemCategory, records: [ItemRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: category.title)
                Text("\(records.count)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(records) { record in
                    NavigationLink(value: record.itemID) {
                        VStack(alignment: .leading, spacing: 6) {
                            ItemThumbnail(
                                item: record.item,
                                image: record.cutout,
                                size: 96,
                                isFramed: record.cutout == nil
                            )
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(Theme.card, in: .rect(cornerRadius: 18, style: .continuous))
                            .shadow(color: Theme.shadow, radius: 8, y: 3)
                            Text(record.name)
                                .font(.caption)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Import

    private static func loader(for item: PhotosPickerItem) -> @Sendable () async -> Data? {
        {
            do {
                return try await item.loadTransferable(type: Data.self)
            } catch {
                Logger.capture.error("Couldn't load a picked photo: \(String(describing: error))")
                return nil
            }
        }
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
