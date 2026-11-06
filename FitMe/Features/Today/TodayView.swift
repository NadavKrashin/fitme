import FitEngine
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.dependencies) private var dependencies
    @Query(sort: \ItemRecord.addedAt) private var records: [ItemRecord]
    @State private var model: TodayModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    TodayContent(model: model, records: records)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Today")
        }
        .task {
            if model == nil {
                model = TodayModel(generator: dependencies.outfitGenerator)
            }
        }
    }
}

private struct TodayContent: View {
    @Bindable var model: TodayModel
    let records: [ItemRecord]

    private var closet: [Item] {
        records.map(\.item)
    }

    var body: some View {
        List {
            Section("Plans") {
                Picker("Occasion", selection: $model.occasion) {
                    ForEach(Occasion.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Feels like \(model.feelsLikeC, format: .number.precision(.fractionLength(0)))°C")
                    Slider(value: $model.feelsLikeC, in: TodayModel.temperatureRange, step: 1)
                        .accessibilityLabel("Feels-like temperature")
                }
                Toggle("Rain expected", isOn: $model.isRainy)
            }

            Section("Suggestions") {
                if closet.isEmpty {
                    Text("Your closet is empty.")
                        .foregroundStyle(.secondary)
                } else if model.suggestions.isEmpty {
                    Text("Nothing in your closet fits this occasion and weather.")
                        .foregroundStyle(.secondary)
                } else {
                    let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.itemID, $0) })
                    ForEach(model.suggestions) { suggestion in
                        OutfitRow(outfit: suggestion) { recordsByID[$0]?.cutout }
                    }
                }
            }
        }
        .task(id: RefreshKey(model: model, closet: closet)) {
            await model.refresh(closet: closet)
        }
    }

    /// Re-run suggestions whenever an input or the closet changes.
    private struct RefreshKey: Equatable {
        let occasion: Occasion
        let feelsLikeC: Double
        let isRainy: Bool
        let itemIDs: [String]

        @MainActor
        init(model: TodayModel, closet: [Item]) {
            occasion = model.occasion
            feelsLikeC = model.feelsLikeC
            isRainy = model.isRainy
            itemIDs = closet.map(\.id)
        }
    }
}

#if DEBUG
#Preview {
    TodayView()
        .environment(\.dependencies, .preview())
        .environment(PreviewData.captureModel)
        .modelContainer(PreviewData.container)
}
#endif
