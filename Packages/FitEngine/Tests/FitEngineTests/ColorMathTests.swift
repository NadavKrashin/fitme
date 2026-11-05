import Testing
@testable import FitEngine

struct ColorMathTests {
    @Test func hexRoundTrip() {
        #expect(RGB(hex: "#1f2a44")?.hex == "#1F2A44")
        #expect(RGB(hex: "#12345") == nil)
    }

    /// Reference values from Björn Ottosson's OKLab post.
    @Test func okLabMatchesReferenceValues() throws {
        let white = try OKLab(#require(RGB(hex: "#FFFFFF")))
        #expect(isClose(white.L, 1))
        #expect(isClose(white.lch.C, 0))

        let red = try OKLab(#require(RGB(hex: "#FF0000")))
        #expect(isClose(red.L, 0.62796))
        #expect(isClose(red.a, 0.22486))
        #expect(isClose(red.b, 0.12585))
        #expect(isClose(red.lch.h, 29.23, tolerance: 0.1))

        let blue = try OKLab(#require(RGB(hex: "#0000FF")))
        #expect(isClose(blue.L, 0.45201))
        #expect(isClose(blue.b, -0.31153))
    }

    @Test(arguments: [
        ("#9A9A9A", Neutrality.neutral), // grey
        ("#1A1A1A", .neutral), // black
        ("#1F2A44", .softNeutral), // navy
        ("#C19A6B", .softNeutral), // camel
        ("#C3B091", .softNeutral), // khaki
        ("#8FA9C7", .softNeutral), // light denim
        ("#B3262E", .chromatic), // red
        ("#D9A21B", .chromatic), // mustard
        ("#6B2D8C", .chromatic), // purple
    ])
    func neutralityClassification(hex: String, expected: Neutrality) throws {
        #expect(try OKLab(#require(RGB(hex: hex))).lch.neutrality == expected)
    }

    @Test func hueDistanceWrapsAround() {
        #expect(isClose(OKLCH.hueDistance(350, 10), 20))
        #expect(isClose(OKLCH.hueDistance(0, 180), 180))
    }
}
