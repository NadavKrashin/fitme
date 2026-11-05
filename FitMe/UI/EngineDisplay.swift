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
