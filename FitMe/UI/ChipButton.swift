import SwiftUI

/// A capsule toggle for filters, tags and occasions.
struct ChipButton: View {
    let title: String
    let isOn: Bool
    /// Fill and text color when selected; defaults to terracotta.
    var tint: (fill: Color, ink: Color)?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isOn ? (tint?.ink ?? Theme.onTerracotta) : Theme.inkMuted)
                .background(isOn ? (tint?.fill ?? Theme.terracotta) : Theme.card, in: .capsule)
                .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.line))
                .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
