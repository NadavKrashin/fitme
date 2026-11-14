import Foundation

/// Colors as menswear color guides name them, fine enough to tell a burgundy sweater from a red one and a rust polo
/// from an orange one, because the guides pair them differently.
enum StyleColor: Hashable, Sendable {
    // Neutrals: they go with each other (with a few named exceptions) and with most colors.
    case black, charcoal, grey, white, navy, denim, lightBlue, beige, khaki, camel, brown, olive
    /// Colors.
    case burgundy, red, pink, rust, orange, mustard, yellow, forest, green, teal, blue, purple

    init(_ color: OKLCH) {
        guard color.neutrality == .chromatic else {
            self = Self.neutral(ColorFamily(color), lightness: color.L)
            return
        }
        self = Self.chromatic(hue: color.h, lightness: color.L)
    }

    private static func neutral(_ family: ColorFamily, lightness: Double) -> StyleColor {
        switch family {
        case .black: .black
        case .charcoal: .charcoal
        case .white: .white
        case .navy: .navy
        case .denim: lightness > 0.75 ? .lightBlue : .denim
        case .beige: .beige
        case .khaki: .khaki
        case .camel: .camel
        case .brown: .brown
        case .olive: .olive
        default: .grey
        }
    }

    private static func chromatic(hue: Double, lightness: Double) -> StyleColor {
        switch hue {
        case ..<15, 345...: lightness > 0.72 ? .pink : (lightness < 0.45 ? .burgundy : .red)
        case ..<45: lightness < 0.45 ? .burgundy : (hue >= 35 && lightness < 0.68 ? .rust : .red)
        case ..<75: lightness < 0.62 ? .rust : .orange
        case ..<115: lightness < 0.78 ? .mustard : .yellow
        case ..<170: lightness < 0.55 ? .forest : .green
        case ..<225: .teal
        case ..<285: lightness > 0.7 ? .lightBlue : .blue
        default: .purple
        }
    }

    var isNeutral: Bool {
        switch self {
        case .black, .charcoal, .grey, .white, .navy, .denim, .lightBlue, .beige, .khaki, .camel, .brown, .olive: true
        default: false
        }
    }

    /// How well two colors go together in one outfit, 0...1, from menswear color guides. Named pairings first; then
    /// neutrals go with each other, and a neutral goes well enough with a color.
    static func pairing(_ a: StyleColor, _ b: StyleColor) -> Double? {
        if a == b {
            return 1
        }
        if let named = named[Set([a, b])] {
            return named
        }
        if a.isNeutral, b.isNeutral {
            return 1
        }
        if a.isNeutral || b.isNeutral {
            return 0.9
        }
        return nil // two colors: judged by hue
    }

    /// Pairings the guides name, good and bad.
    private static let named: [Set<StyleColor>: Double] = {
        var table: [Set<StyleColor>: Double] = [
            // Dark on dark that reads as a mistake, and the contested brown with black.
            [.navy, .black]: 0.6,
            [.brown, .black]: 0.75,
            [.navy, .charcoal]: 0.85,
            [.burgundy, .black]: 0.8,
            // Two colors that clash or read as a costume.
            [.red, .forest]: 0.4,
            [.red, .green]: 0.35,
            [.orange, .purple]: 0.4,
            [.burgundy, .forest]: 0.85,
            [.rust, .forest]: 0.85,
            [.pink, .lightBlue]: 0.95,
        ]
        let classics: [StyleColor: [StyleColor]] = [
            .navy: [.burgundy, .rust, .pink, .forest, .mustard, .red],
            .grey: [.burgundy, .pink, .forest, .mustard],
            .charcoal: [.burgundy, .pink, .rust],
            .white: [.burgundy, .red, .pink, .rust, .orange, .mustard, .yellow, .forest, .green, .teal, .blue, .purple],
            .beige: [.forest, .burgundy, .rust, .blue],
            .khaki: [.forest, .burgundy, .rust, .blue],
            .camel: [.forest, .burgundy, .rust],
            .brown: [.pink, .rust, .forest, .mustard, .blue],
            .olive: [.burgundy, .rust, .mustard],
            .denim: [.rust, .burgundy, .forest, .mustard, .red, .pink],
            .black: [.red, .pink],
        ]
        for (neutral, colors) in classics {
            for color in colors {
                table[Set([neutral, color])] = 1
            }
        }
        return table
    }()
}
