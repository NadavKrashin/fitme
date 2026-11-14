import SwiftUI

/// Asked once, before anything is sent to Claude: what goes to Anthropic, for what, and that FitMe works without it.
struct AIConsentView: View {
    let onAnswer: (Bool) -> Void
    /// Room for a row's icon, growing with the text size so large icons don't overlap the text.
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 28

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.terracotta)
                    .accessibilityHidden(true)
                Text("Before you start")
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.ink)
                Text("FitMe uses Claude, an AI made by Anthropic. With your permission, it sends:")
                    .foregroundStyle(Theme.ink)
                point(
                    "camera",
                    title: "Photos of clothes you add",
                    detail: "and the shop page you pick with Find online, to name each piece and tag its colors, fit "
                        + "and fabric."
                )
                point(
                    "text.bubble",
                    title: "Descriptions of your clothes",
                    detail: "with the occasion and the weather, when you ask the stylist or check a bag. No photos."
                )
                Text("Your calendar never leaves your iPhone, and the weather only uses your approximate location.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                Text("Without Claude you tag clothes yourself, and outfit suggestions still work. You can change this "
                    + "anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                Link("Read the privacy policy", destination: PrivacyLinks.policy)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button("Allow") { onAnswer(true) }
                    .buttonStyle(.pill(.primary))
                    .frame(maxWidth: .infinity)
                Button("Not now") { onAnswer(false) }
                    .buttonStyle(.pill(.quiet))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
            .background(Theme.canvas)
        }
        .background(Theme.canvas)
        .tint(Theme.terracotta)
        .interactiveDismissDisabled()
    }

    private func point(_ symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.terracotta)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                Text(detail).font(.subheadline).foregroundStyle(Theme.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    AIConsentView { _ in }
}
#endif
