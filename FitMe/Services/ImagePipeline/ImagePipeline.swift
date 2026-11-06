import CoreImage
import FitEngine
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers
import Vision

/// Everything derived from one item photo.
struct ProcessedPhoto: Sendable {
    /// The original photo, oriented and downscaled, kept for re-tagging later.
    let photoJPEG: Data
    /// The item alone on a transparent square: what the closet and collages show.
    let cutoutPNG: Data
    /// The item on white, sized for the tagging model.
    let taggingJPEG: Data
    let colors: [ItemColor]
    /// False when subject lift failed and the images contain the original background.
    let hasCutout: Bool
}

protocol PhotoProcessing: Sendable {
    func process(_ imageData: Data) async throws -> ProcessedPhoto
}

enum ImagePipelineError: Error {
    case unreadableImage
    case encodingFailed
}

struct ImagePipeline: PhotoProcessing {
    private static let photoMaxPixels = 1600
    private static let cutoutSide = 512
    private static let taggingSide = 1024
    /// Pixels sampled for color extraction: plenty for k-means, cheap to cluster.
    private static let colorSampleSide = 64
    /// Share of each side left empty around the item.
    private static let padding = 0.06

    /// Vision and image encoding are slow and synchronous: keep them off the main actor.
    @concurrent
    func process(_ imageData: Data) async throws -> ProcessedPhoto {
        let photo = try Self.orientedImage(from: imageData, maxPixels: Self.photoMaxPixels)
        let cutout = Self.liftSubject(from: photo)
        let subject = cutout ?? photo

        return try ProcessedPhoto(
            photoJPEG: Self.encode(photo, as: .jpeg),
            cutoutPNG: Self.encode(Self.squared(subject, side: Self.cutoutSide, background: nil), as: .png),
            taggingJPEG: Self.encode(Self.squared(subject, side: Self.taggingSide, background: .white), as: .jpeg),
            colors: ColorExtractor.dominantColors(in: Self.samplePixels(of: subject, onlyOpaque: cutout != nil)),
            hasCutout: cutout != nil
        )
    }

    /// Decodes with EXIF orientation applied, downscaled so the long edge is at most `maxPixels`.
    static func orientedImage(from data: Data, maxPixels: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw ImagePipelineError.unreadableImage }
        return image
    }

    /// The foreground subject, cropped to its bounds with a transparent background, or nil if Vision can't find
    /// one (e.g. no subject, or the simulator, which lacks the model).
    static func liftSubject(from image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        } catch {
            Logger.imagePipeline.notice("Subject lift unavailable, using the full photo: \(String(describing: error))")
            return nil
        }
    }

    /// Fits the image, centered with padding, into a square canvas.
    static func squared(_ image: CGImage, side: Int, background: CGColor?) throws -> CGImage {
        guard let context = rgbaContext(side: side) else { throw ImagePipelineError.encodingFailed }
        if let background {
            context.setFillColor(background)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        let available = Double(side) * (1 - 2 * padding)
        let scale = available / Double(max(image.width, image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(
            x: (Double(side) - width) / 2,
            y: (Double(side) - height) / 2,
            width: width,
            height: height
        ))
        guard let result = context.makeImage() else { throw ImagePipelineError.encodingFailed }
        return result
    }

    /// Downsampled pixels for color extraction. With a cutout, only the item's (opaque) pixels count; without one,
    /// the central area stands in for the item.
    static func samplePixels(of image: CGImage, onlyOpaque: Bool) -> [RGB] {
        let side = colorSampleSide
        guard let context = rgbaContext(side: side) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return [] }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        var pixels: [RGB] = []
        let center = (side / 4) ..< (side * 3 / 4)
        for y in 0 ..< side {
            for x in 0 ..< side {
                let offset = (y * side + x) * 4
                let alpha = Double(bytes[offset + 3]) / 255
                let include = onlyOpaque ? alpha > 0.9 : (center.contains(x) && center.contains(y))
                guard include, alpha > 0 else { continue }
                // Premultiplied: divide alpha back out.
                pixels.append(RGB(
                    r: Double(bytes[offset]) / 255 / alpha,
                    g: Double(bytes[offset + 1]) / 255 / alpha,
                    b: Double(bytes[offset + 2]) / 255 / alpha
                ))
            }
        }
        return pixels
    }

    static func encode(_ image: CGImage, as type: UTType) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ImagePipelineError.encodingFailed
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImagePipelineError.encodingFailed }
        return data as Data
    }

    private static func rgbaContext(side: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

private extension CGColor {
    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
}
