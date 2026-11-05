#!/usr/bin/env swift
// Renders the 1024×1024 app icons for production and staging into the asset catalog.
// Usage: swift scripts/make-app-icons.swift
import AppKit

let size = 1024
let catalog = "FitMe/Resources/Assets.xcassets"

func render(label: String?, to path: String) throws {
    // App Store icons must not have an alpha channel, so draw into an opaque RGB context.
    guard let cgContext = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let context = NSGraphicsContext(cgContext: cgContext, flipped: false)
    NSGraphicsContext.current = context
    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    let gradient = NSGradient(
        starting: NSColor(red: 0.13, green: 0.19, blue: 0.30, alpha: 1),
        ending: NSColor(red: 0.42, green: 0.26, blue: 0.15, alpha: 1)
    )
    gradient?.draw(in: rect, angle: -60)

    let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .light)
        .applying(.init(paletteColors: [.white]))
    if let hanger = NSImage(systemSymbolName: "hanger", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symbolSize = hanger.size
        let origin = NSPoint(x: (CGFloat(size) - symbolSize.width) / 2, y: (CGFloat(size) - symbolSize.height) / 2 + 40)
        hanger.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    if let label {
        NSColor(red: 0.96, green: 0.55, blue: 0.13, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: size, height: 200).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 120, weight: .heavy),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        text.draw(at: NSPoint(x: (CGFloat(size) - text.size().width) / 2, y: (200 - text.size().height) / 2))
    }

    NSGraphicsContext.current = nil
    guard let image = cgContext.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: URL(fileURLWithPath: path))
}

try render(label: nil, to: "\(catalog)/AppIcon.appiconset/icon-1024.png")
try render(label: "STAGING", to: "\(catalog)/AppIcon-Staging.appiconset/icon-1024.png")
print("Icons written to \(catalog)")
