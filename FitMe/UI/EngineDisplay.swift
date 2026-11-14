import FitEngine
import SwiftUI

extension Occasion {
    var title: String {
        switch self {
        case .casual: "Casual"
        case .smartCasual: "Smart casual"
        case .work: "Work"
        case .date: "Date"
        case .formal: "Formal"
        case .sport: "Sport"
        case .beach: "Beach"
        case .travel: "Travel"
        }
    }
}

extension Palette {
    var title: String {
        switch self {
        case .neutral: "Neutral"
        case .balanced: "Mixed"
        case .colorful: "Colorful"
        }
    }
}

extension ItemCategory {
    var title: String {
        switch self {
        case .outerwear: "Outerwear"
        case .midLayer: "Layers"
        case .top: "Tops"
        case .onePiece: "Dresses & one-pieces"
        case .bottom: "Bottoms"
        case .shoes: "Shoes"
        case .bag: "Bags"
        case .accessory: "Accessories"
        }
    }

    var symbolName: String {
        switch self {
        case .outerwear, .midLayer: "hanger"
        case .top: "tshirt"
        case .onePiece: "figure.stand.dress"
        case .bottom: "rectangle.portrait"
        case .shoes: "shoe"
        case .bag: "handbag"
        case .accessory: "eyeglasses"
        }
    }
}

extension ItemColor {
    var swiftUIColor: Color {
        let rgb = RGB(hex: hex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// Black or white, whichever reads better on top of this color.
    var contrastingColor: Color {
        lab.L > 0.6 ? .black : .white
    }
}

extension ItemPattern {
    var title: String {
        switch self {
        case .solid: "Solid"
        case .textured: "Textured"
        case .stripe: "Stripes"
        case .check: "Check"
        case .floral: "Floral"
        case .graphic: "Graphic"
        case .print: "Print"
        case .other: "Other"
        }
    }
}

extension Fit {
    var title: String {
        rawValue.capitalized
    }
}

extension StyleTag {
    var title: String {
        rawValue.capitalized
    }
}

/// Labels for the engine's 1–5 scales, matching the definitions given to the tagging model.
enum ScaleLabels {
    static func formality(_ value: Int) -> String {
        switch value {
        case 1: "Lounge"
        case 2: "Casual"
        case 3: "Smart casual"
        case 4: "Dressy"
        default: "Black tie"
        }
    }

    static func warmth(_ value: Int) -> String {
        switch value {
        case 1: "Very light"
        case 2: "Light"
        case 3: "Medium"
        case 4: "Warm"
        default: "Very warm"
        }
    }
}

extension ItemColor {
    /// A plain-language approximation ("navy", "dark green"), for the stylist and accessibility.
    var name: String {
        guard lch.neutrality == .chromatic else { return family.name }
        if lch.L < 0.45 {
            return "dark \(family.name)"
        }
        if lch.L > 0.8, lch.C < 0.12 {
            return "light \(family.name)"
        }
        return family.name
    }
}

extension ColorFamily {
    var name: String {
        switch self {
        case .charcoal: "dark grey"
        case .denim: "denim blue"
        case .brown: "dark brown"
        default: rawValue
        }
    }

    /// A typical shade of the family, for showing a learned pairing.
    var swatch: Color {
        let hex = switch self {
        case .black: "#1A1A1A"
        case .charcoal: "#4A4A4C"
        case .grey: "#9A9A9A"
        case .white: "#F5F5F2"
        case .navy: "#1F2A44"
        case .denim: "#6F8FAF"
        case .beige: "#E3D5BC"
        case .brown: "#5C3B26"
        case .camel: "#C19A6B"
        case .khaki: "#C3B091"
        case .olive: "#5A6140"
        case .pink: "#E7A1B0"
        case .red: "#B83A32"
        case .orange: "#D9772E"
        case .yellow: "#E3C04A"
        case .green: "#3F7A52"
        case .teal: "#2F7F7A"
        case .blue: "#3A6EA5"
        case .purple: "#6E4C8C"
        }
        return ItemColor(hex: hex).swiftUIColor
    }
}
