import Testing
@testable import FitEngine

struct ColorExtractorTests {
    @Test(arguments: ["#1F2A44", "#B3262E", "#F5F5F2", "#C19A6B"])
    func labRoundTripsToTheSameHex(hex: String) throws {
        let lab = try OKLab(#require(RGB(hex: hex)))
        #expect(ColorExtractor.rgb(from: lab).hex == hex)
    }

    @Test func solidItemGivesOneColor() throws {
        let navy = try #require(RGB(hex: "#1F2A44"))
        let colors = ColorExtractor.dominantColors(in: Array(repeating: navy, count: 400))
        #expect(colors.count == 1)
        #expect(colors.first?.hex == "#1F2A44")
        #expect(colors.first?.proportion == 1)
    }

    @Test func shadingMergesIntoOneColor() {
        // A navy shirt photographed with soft shading: many slightly different navies.
        let pixels = (0 ..< 300).map { i in
            RGB(r: 0.12 + Double(i % 10) * 0.004, g: 0.16 + Double(i % 10) * 0.004, b: 0.27 + Double(i % 10) * 0.004)
        }
        let colors = ColorExtractor.dominantColors(in: pixels)
        #expect(colors.count == 1)
        #expect(colors.first?.lch.neutrality == .softNeutral)
    }

    @Test func stripesGiveTwoColorsWithTheirShares() throws {
        let cream = try #require(RGB(hex: "#F2F0EA"))
        let navy = try #require(RGB(hex: "#1F2A44"))
        let pixels = Array(repeating: cream, count: 600) + Array(repeating: navy, count: 400)

        let colors = ColorExtractor.dominantColors(in: pixels)

        #expect(colors.map(\.hex) == ["#F2F0EA", "#1F2A44"])
        #expect(isClose(colors[0].proportion, 0.6))
        #expect(isClose(colors[1].proportion, 0.4))
    }

    @Test func smallSpecksAreIgnored() throws {
        let grey = try #require(RGB(hex: "#9A9A9A"))
        let logo = try #require(RGB(hex: "#E04E39"))
        let pixels = Array(repeating: grey, count: 970) + Array(repeating: logo, count: 30)
        #expect(ColorExtractor.dominantColors(in: pixels).map(\.hex) == ["#9A9A9A"])
    }

    @Test func isDeterministic() throws {
        let pixels = try ["#F1E6D2", "#C2463E", "#3E6B4A"].flatMap { hex in
            try Array(repeating: #require(RGB(hex: hex)), count: 200)
        }
        #expect(ColorExtractor.dominantColors(in: pixels) == ColorExtractor.dominantColors(in: pixels.reversed()))
    }

    @Test func emptyInputGivesNoColors() {
        #expect(ColorExtractor.dominantColors(in: []).isEmpty)
    }
}
