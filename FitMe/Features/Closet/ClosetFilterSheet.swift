import FitEngine
import SwiftUI

/// Narrows the closet by color, dress code and brand. Only choices the closet actually has are offered.
struct ClosetFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: ClosetFilter
    let options: ClosetFilter.Options
    /// Pieces the current filter shows, for the Done button.
    let matchingCount: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Color") {
                        ForEach(options.colors, id: \.self) { family in
                            colorChip(family)
                        }
                    }
                    section("Dress code") {
                        ForEach(options.formality, id: \.self) { level in
                            ChipButton(title: ScaleLabels.formality(level), isOn: filter.formality.contains(level)) {
                                filter.formality.formSymmetricDifference([level])
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Brand")
                        if options.brands.isEmpty {
                            Text("Brands show up here once you match pieces to their shop with Find online.")
                                .font(.callout)
                                .foregroundStyle(Theme.inkMuted)
                        } else {
                            FlowLayout {
                                ForEach(options.brands, id: \.self) { brand in
                                    ChipButton(title: brand, isOn: filter.brands.contains(brand)) {
                                        filter.brands.formSymmetricDifference([brand])
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(Theme.gutter)
            }
            .editorialCanvas()
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { filter.clearRefinements() }
                        .disabled(filter.refinementCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(matchingCount == 1 ? "Show 1 piece" : "Show \(matchingCount) pieces") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder chips: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            FlowLayout { chips() }
        }
    }

    private func colorChip(_ family: ColorFamily) -> some View {
        let isOn = filter.colors.contains(family)
        return Button {
            filter.colors.formSymmetricDifference([family])
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(family.swatch)
                    .frame(width: 16, height: 16)
                    .overlay { Circle().strokeBorder(Theme.line, lineWidth: 1) }
                Text(family.name.capitalized)
                    .font(.subheadline.weight(isOn ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isOn ? Theme.onTerracotta : Theme.inkMuted)
            .background(isOn ? Theme.terracotta : Theme.card, in: .capsule)
            .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.line))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
