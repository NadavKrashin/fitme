import FitEngine
import Foundation
import ImageIO
import Testing
import UIKit
@testable import FitMe

struct ImagePipelineTests {
    /// A red square filling the middle of a white photo.
    private func redSquarePhoto() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300))
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1).setFill()
            context.fill(CGRect(x: 80, y: 40, width: 240, height: 220))
        }
    }

    private func pixelSize(of data: Data) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    @Test func producesAllOutputsAndFindsTheRed() async throws {
        let result = try await ImagePipeline().process(redSquarePhoto())

        #expect(try pixelSize(of: result.photoJPEG) == (400, 300))
        #expect(try pixelSize(of: result.cutoutPNG) == (512, 512))
        #expect(try pixelSize(of: result.taggingJPEG) == (1024, 1024))
        let dominant = try #require(result.colors.first)
        #expect(dominant.lch.neutrality == .chromatic)
        #expect(OKLCH.hueDistance(dominant.lch.h, 29) < 15, "expected red, got \(dominant.hex)")
    }

    @Test func rejectsDataThatIsNotAnImage() async {
        await #expect(throws: ImagePipelineError.self) { try await ImagePipeline().process(Data("nope".utf8)) }
    }
}
