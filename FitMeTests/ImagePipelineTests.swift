import FitEngine
import Foundation
import ImageIO
import Testing
import UIKit
@testable import FitMe

struct ImagePipelineTests {
    /// A red square filling the middle of a white photo.
    private func redSquarePhoto() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // pixels, not points: the default uses the screen scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format)
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

    /// Red on the left, blue on the right, on white.
    private func redAndBluePhoto() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200), format: format)
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
            UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1).setFill()
            context.fill(CGRect(x: 40, y: 40, width: 120, height: 120))
            UIColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 240, y: 40, width: 120, height: 120))
        }
    }

    @Test func cropKeepsOnlyWhatIsInsideTheBox() async throws {
        let pipeline = ImagePipeline()
        let photo = try await pipeline.process(redAndBluePhoto())
        // The 400x200 photo sits in the square at x 6%...94% and y 28%...72%; its left half is x 6%...50%.
        let cropped = try await pipeline.crop(photo, to: ItemBox(x0: 60, y0: 280, x1: 490, y1: 720))

        #expect(try pixelSize(of: cropped.cutoutPNG) == (512, 512))
        #expect(cropped.colors.allSatisfy { OKLCH.hueDistance($0.lch.h, 264) > 40 }, "blue should be cropped away")
        let dominant = try #require(cropped.colors.first)
        #expect(OKLCH.hueDistance(dominant.lch.h, 29) < 15, "expected red, got \(dominant.hex)")
    }

    @Test func pixelRectAddsAMarginAndStaysInBounds() {
        let rect = ImagePipeline.pixelRect(for: ItemBox(x0: 0, y0: 500, x1: 500, y1: 1000), side: 1000)
        #expect(rect == CGRect(x: 0, y: 470, width: 530, height: 530))
    }

    @Test func rejectsDataThatIsNotAnImage() async {
        await #expect(throws: ImagePipelineError.self) { try await ImagePipeline().process(Data("nope".utf8)) }
    }
}
