import Foundation

/// A named color group, coarse enough that "navy chinos with a white shirt" and "navy jeans with a white tee" share
/// the same pairing. Used to learn color preferences and to name colors for people.
public enum ColorFamily: String, Codable, CaseIterable, Sendable {
    case black, charcoal, grey, white
    case navy, denim, beige, brown, camel, khaki, olive
    case pink, red, orange, yellow, green, teal, blue, purple

    public init(_ color: OKLCH) {
        switch color.neutrality {
        case .neutral: self = Self.neutral(lightness: color.L)
        case .softNeutral: self = Self.softNeutral(lightness: color.L, hue: color.h)
        case .chromatic: self = Self.chromatic(hue: color.h)
        }
    }

    private static func neutral(lightness: Double) -> ColorFamily {
        if lightness < 0.3 {
            return .black
        }
        if lightness > 0.9 {
            return .white
        }
        return lightness < 0.55 ? .charcoal : .grey
    }

    private static func softNeutral(lightness: Double, hue: Double) -> ColorFamily {
        if (215 ... 275).contains(hue) {
            return lightness < 0.4 ? .navy : .denim
        }
        if lightness > 0.8 {
            return .beige
        }
        if hue < 75 {
            return lightness < 0.45 ? .brown : .camel
        }
        return lightness > 0.65 ? .khaki : .olive
    }

    private static func chromatic(hue: Double) -> ColorFamily {
        switch hue {
        case ..<15, 345...: .pink
        case ..<45: .red
        case ..<75: .orange
        case ..<115: .yellow
        case ..<170: .green
        case ..<225: .teal
        case ..<285: .blue
        default: .purple
        }
    }
}

public extension ItemColor {
    var family: ColorFamily {
        ColorFamily(lch)
    }
}
