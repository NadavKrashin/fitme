import FitEngine
import SwiftUI
import UIKit

/// The warm editorial look: cream paper, ink type, terracotta and sage accents, serif headlines.
/// Every color has a light and a dark value; views never hard-code colors.
enum Theme {
    // MARK: Palette

    static let canvas = dynamic(light: 0xF6F1E9, dark: 0x1B1815)
    static let card = dynamic(light: 0xFFFDF9, dark: 0x25211D)
    static let ink = dynamic(light: 0x2C2C2A, dark: 0xF3EDE4)
    static let inkMuted = dynamic(light: 0x7A6B5D, dark: 0xA89A8B)
    static let line = dynamic(light: 0xE7DFD3, dark: 0x3A342E)
    static let terracotta = dynamic(light: 0xB4532A, dark: 0xD9774E)
    static let onTerracotta = dynamic(light: 0xFFF7EF, dark: 0x1E0F07)
    static let sage = dynamic(light: 0xE3E8DA, dark: 0x2F362A)
    static let sageInk = dynamic(light: 0x3F4A33, dark: 0xC9D4BC)
    static let butter = dynamic(light: 0xF3E3C3, dark: 0x3D3220)
    static let butterInk = dynamic(light: 0x6B4F24, dark: 0xEBD3A6)
    static let shadow = Color.black.opacity(0.06)

    // MARK: Type

    /// Screen titles.
    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// Section and card titles.
    static func title(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    // MARK: Shape

    static let cardRadius: CGFloat = 22
    static let gutter: CGFloat = 20

    /// Serif navigation titles on the paper canvas, applied once at launch to every navigation bar.
    @MainActor
    static func applyNavigationBarAppearance() {
        func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        let inkColor = UIColor(ink)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [.font: serif(36, .regular), .foregroundColor: inkColor]
        appearance.titleTextAttributes = [.font: serif(18, .medium), .foregroundColor: inkColor]

        let scrolled = appearance.copy()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundColor = UIColor(canvas)
        scrolled.shadowColor = UIColor(line)
        scrolled.largeTitleTextAttributes = appearance.largeTitleTextAttributes
        scrolled.titleTextAttributes = appearance.titleTextAttributes

        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
    }

    /// A soft tint per occasion so plans read at a glance, and the app isn't one color.
    static func tint(for occasion: Occasion) -> (fill: Color, ink: Color) {
        switch occasion {
        case .casual: (sage, sageInk)
        case .smartCasual: (butter, butterInk)
        case .work: (dynamic(light: 0xDDE3EA, dark: 0x27303B), dynamic(light: 0x2E3E52, dark: 0xC7D3E2))
        case .date: (dynamic(light: 0xF2DCD6, dark: 0x3E2622), dynamic(light: 0x7A3328, dark: 0xF0C4B9))
        case .formal: (dynamic(light: 0xE4E0EC, dark: 0x2E2A38), dynamic(light: 0x3A3352, dark: 0xD3CDE3))
        case .sport: (dynamic(light: 0xF3E6C4, dark: 0x3A3119), dynamic(light: 0x6B5413, dark: 0xEBD69A))
        case .beach: (dynamic(light: 0xD8E9E6, dark: 0x1F3633), dynamic(light: 0x1F5A52, dark: 0xB5DDD6))
        case .travel: (dynamic(light: 0xEBDDD3, dark: 0x3A2A21), dynamic(light: 0x6E3F28, dark: 0xE8C6B1))
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
