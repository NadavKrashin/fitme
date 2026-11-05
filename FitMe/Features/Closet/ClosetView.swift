import FitEngine
import SwiftData
import SwiftUI

struct ClosetView: View {
    @Query(sort: \ItemRecord.name) private var records: [ItemRecord]

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "Your closet is empty",
                        systemImage: "hanger",
                        description: Text(emptyHint)
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(sections, id: \.category) { section in
                                categorySection(section.category, items: section.items)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Closet")
        }
    }

    private var sections: [(category: ItemCategory, items: [Item])] {
        let items = records.map(\.item)
        return Dictionary(grouping: items, by: \.category)
            .sorted { $0.key.layerOrder < $1.key.layerOrder }
            .map { ($0.key, $0.value) }
    }

    private var emptyHint: String {
        switch AppEnvironment.current {
        case .staging: "Load the demo closet from Settings to try things out."
        case .production: "Adding items from photos is coming next."
        }
    }

    private func categorySection(_ category: ItemCategory, items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(category.title) · \(items.count)")
                .font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    VStack(spacing: 4) {
                        ItemThumbnail(item: item, size: 72)
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    ClosetView()
        .modelContainer(PreviewData.container)
}
#endif
