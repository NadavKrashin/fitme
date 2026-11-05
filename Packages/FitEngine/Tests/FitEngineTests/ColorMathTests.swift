import XCTest
@testable import FitEngine

final class ColorMathTests: XCTestCase {
    func testHexRoundTrip() {
        XCTAssertEqual(RGB(hex: "#1f2a44")?.hex, "#1F2A44")
        XCTAssertNil(RGB(hex: "#12345"))
    }

    func testOKLabReferenceValues() {
        let white = OKLab(RGB(hex: "#FFFFFF")!)
        XCTAssertEqual(white.L, 1, accuracy: 1e-3)
        XCTAssertEqual(white.lch.C, 0, accuracy: 1e-3)

        XCTAssertEqual(OKLab(RGB(hex: "#000000")!).L, 0, accuracy: 1e-6)

        // Reference values from Björn Ottosson's OKLab post.
        let red = OKLab(RGB(hex: "#FF0000")!)
        XCTAssertEqual(red.L, 0.62796, accuracy: 1e-3)
        XCTAssertEqual(red.a, 0.22486, accuracy: 1e-3)
        XCTAssertEqual(red.b, 0.12585, accuracy: 1e-3)
        XCTAssertEqual(red.lch.h, 29.23, accuracy: 0.1)

        let blue = OKLab(RGB(hex: "#0000FF")!)
        XCTAssertEqual(blue.L, 0.45201, accuracy: 1e-3)
        XCTAssertEqual(blue.b, -0.31153, accuracy: 1e-3)
    }

    func testNeutralityClassification() {
        func n(_ hex: String) -> Neutrality { OKLab(RGB(hex: hex)!).lch.neutrality }
        XCTAssertEqual(n("#9A9A9A"), .neutral)    // grey
        XCTAssertEqual(n("#1A1A1A"), .neutral)    // black
        XCTAssertEqual(n("#1F2A44"), .softNeutral) // navy
        XCTAssertEqual(n("#C19A6B"), .softNeutral) // camel
        XCTAssertEqual(n("#C3B091"), .softNeutral) // khaki
        XCTAssertEqual(n("#8FA9C7"), .softNeutral) // light denim
        XCTAssertEqual(n("#B3262E"), .chromatic)   // red
        XCTAssertEqual(n("#D9A21B"), .chromatic)   // mustard
        XCTAssertEqual(n("#6B2D8C"), .chromatic)   // purple
    }

    func testHueDistanceWraps() {
        XCTAssertEqual(OKLCH.hueDistance(350, 10), 20, accuracy: 1e-9)
        XCTAssertEqual(OKLCH.hueDistance(0, 180), 180, accuracy: 1e-9)
    }
}
