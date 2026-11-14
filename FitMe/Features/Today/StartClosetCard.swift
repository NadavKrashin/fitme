import SwiftUI

/// Today with an empty closet: nothing to suggest yet, so the way to add clothes instead of empty controls.
struct StartClosetCard: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "hanger")
                .font(.title)
                .foregroundStyle(Theme.terracotta)
                .accessibilityHidden(true)
            Text("Outfits start with your clothes")
                .font(Theme.title(22))
                .foregroundStyle(Theme.ink)
            Text("Add a few tops, bottoms and shoes, and FitMe suggests what to wear for today's weather.")
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
            HStack(spacing: 10) {
                Button("Take photos") { navigation.addClothes(.camera) }
                    .buttonStyle(.pill(.accent))
                Button("Choose from library") { navigation.addClothes(.library) }
                    .buttonStyle(.pill(.quiet))
            }
            .padding(.top, 4)
        }
        .card(padding: 22)
    }
}
