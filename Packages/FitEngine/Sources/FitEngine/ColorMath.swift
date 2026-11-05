import Foundation

/// An sRGB color with components in 0...1.
public struct RGB: Hashable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parses `#RRGGBB` or `RRGGBB`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
    }

    public var hex: String {
        func byte(_ c: Double) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

/// Perceptual color space (Björn Ottosson's OKLab). Distances here track how different colors look.
public struct OKLab: Hashable {
    public var L: Double
    public var a: Double
    public var b: Double

    public init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }

    public init(_ rgb: RGB) {
        let r = OKLab.linearize(rgb.r), g = OKLab.linearize(rgb.g), b = OKLab.linearize(rgb.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        self.b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    public func distance(to other: OKLab) -> Double {
        let dL = L - other.L, da = a - other.a, db = b - other.b
        return (dL * dL + da * da + db * db).squareRoot()
    }

    public var lch: OKLCH {
        var h = atan2(b, a) * 180 / .pi
        if h < 0 { h += 360 }
        return OKLCH(L: L, C: (a * a + b * b).squareRoot(), h: h)
    }

    static func linearize(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}

/// How a color behaves when styling an outfit.
public enum Neutrality: Equatable {
    /// Black, white, greys, near-greys: go with anything.
    case neutral
    /// Navy, denim, camel, khaki, olive, chocolate: muted colors that style like neutrals.
    case softNeutral
    /// A real color that has to harmonize with the other colors in the outfit.
    case chromatic
}

/// OKLab in polar form: lightness, chroma (colorfulness), hue in degrees.
public struct OKLCH: Hashable {
    public var L: Double
    public var C: Double
    public var h: Double

    public var neutrality: Neutrality {
        if C < 0.035 { return .neutral }
        guard C < 0.10 else { return .chromatic }
        if L < 0.40 { return .softNeutral }                     // navy, chocolate, dark olive
        if (40...135).contains(h) { return .softNeutral }       // camel, khaki, tan, olive
        if (215...275).contains(h) && C < 0.09 { return .softNeutral } // denim, chambray, light blue
        return .chromatic
    }

    /// Shortest angular distance between two hues, 0...180.
    public static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
