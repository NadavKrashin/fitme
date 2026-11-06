import FitEngine
import SwiftUI

/// Form sections for editing an item's tags. Used when reviewing a new item and when editing an existing one.
struct ItemEditorSections: View {
    @Binding var item: Item

    var body: some View {
        Group {
            Section("Item") {
                TextField("Name", text: $item.name)
                Picker("Category", selection: $item.category) {
                    ForEach(ItemCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Type (e.g. chinos)", text: subcategory)
            }

            Section("Look") {
                Picker("Pattern", selection: $item.pattern) {
                    ForEach(ItemPattern.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Fit", selection: $item.fit) {
                    ForEach(Fit.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Statement piece", isOn: $item.isStatement)
                if !item.colors.isEmpty {
                    LabeledContent("Colors") {
                        HStack(spacing: 4) {
                            ForEach(item.colors, id: \.hex) { color in
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .overlay(Circle().strokeBorder(.secondary.opacity(0.4)))
                                    .frame(width: 22, height: 22)
                                    .accessibilityLabel("\(color.hex), \(Int(color.proportion * 100)) percent")
                            }
                        }
                    }
                }
            }

            Section("When to wear") {
                Picker("Formality", selection: $item.formality) {
                    ForEach(1 ... 5, id: \.self) { Text("\($0) · \(ScaleLabels.formality($0))").tag($0) }
                }
                Picker("Warmth", selection: $item.warmth) {
                    ForEach(1 ... 5, id: \.self) { Text("\($0) · \(ScaleLabels.warmth($0))").tag($0) }
                }
                Toggle("Water resistant", isOn: $item.waterResistant)
            }

            Section("Style") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(StyleTag.allCases, id: \.self) { tag in
                            ChipButton(title: tag.title, isOn: item.styleTags.contains(tag)) { toggle(tag) }
                        }
                    }
                }
            }
        }
        .editorialRow()
        .tint(Theme.terracotta)
    }

    private var subcategory: Binding<String> {
        Binding(
            get: { item.subcategory ?? "" },
            set: { item.subcategory = $0.isEmpty ? nil : $0 }
        )
    }

    private func toggle(_ tag: StyleTag) {
        if item.styleTags.contains(tag) {
            item.styleTags.remove(tag)
        } else {
            item.styleTags.insert(tag)
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var item = PreviewData.items[0]
    Form { ItemEditorSections(item: $item) }
}
#endif
