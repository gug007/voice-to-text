#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// Gradient background colors — iOS-style rounded-square icon
let gradientTop = NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
let gradientBottom = NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)

func drawIcon(pixelSize: CGFloat) -> NSBitmapImageRep {
    let rect = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixelSize),
        pixelsHigh: Int(pixelSize),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        fatalError("Failed to create bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // Rounded square background with gradient
    let cornerRadius = pixelSize * 0.225
    let backgroundPath = NSBezierPath(
        roundedRect: rect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    let gradient = NSGradient(colors: [gradientTop, gradientBottom])!
    gradient.draw(in: backgroundPath, angle: 270)

    // Voice bars: five level bars centred on the icon
    let s = pixelSize
    NSColor.white.setFill()

    let barWidth = s * 10 / 120
    let bars: [(center: CGFloat, height: CGFloat)] = [
        (28, 20), (44, 46), (60, 66), (76, 38), (92, 24),
    ]
    for bar in bars {
        let height = s * bar.height / 120
        let barRect = CGRect(
            x: s * bar.center / 120 - barWidth / 2,
            y: (s - height) / 2,
            width: barWidth,
            height: height
        )
        NSBezierPath(
            roundedRect: barRect,
            xRadius: barWidth / 2,
            yRadius: barWidth / 2
        ).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func savePNG(_ bitmap: NSBitmapImageRep, to path: String) {
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG at \(path)")
    }
    try! data.write(to: URL(fileURLWithPath: path))
}

// Output directory defaults to the AppIcon asset set
let defaultOutput = "VoiceToText/VoiceToText/Assets.xcassets/AppIcon.appiconset"
let outputDir = CommandLine.arguments.dropFirst().first ?? defaultOutput

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

struct IconSize {
    let filename: String
    let pixels: Int
    let size: String
    let scale: String
}

let icons: [IconSize] = [
    .init(filename: "icon_16x16.png",      pixels: 16,   size: "16x16",   scale: "1x"),
    .init(filename: "icon_16x16@2x.png",   pixels: 32,   size: "16x16",   scale: "2x"),
    .init(filename: "icon_32x32.png",      pixels: 32,   size: "32x32",   scale: "1x"),
    .init(filename: "icon_32x32@2x.png",   pixels: 64,   size: "32x32",   scale: "2x"),
    .init(filename: "icon_128x128.png",    pixels: 128,  size: "128x128", scale: "1x"),
    .init(filename: "icon_128x128@2x.png", pixels: 256,  size: "128x128", scale: "2x"),
    .init(filename: "icon_256x256.png",    pixels: 256,  size: "256x256", scale: "1x"),
    .init(filename: "icon_256x256@2x.png", pixels: 512,  size: "256x256", scale: "2x"),
    .init(filename: "icon_512x512.png",    pixels: 512,  size: "512x512", scale: "1x"),
    .init(filename: "icon_512x512@2x.png", pixels: 1024, size: "512x512", scale: "2x"),
]

for icon in icons {
    let bitmap = drawIcon(pixelSize: CGFloat(icon.pixels))
    savePNG(bitmap, to: "\(outputDir)/\(icon.filename)")
    print("wrote \(icon.filename) (\(icon.pixels)x\(icon.pixels))")
}

// Write Contents.json
var imageEntries: [String] = []
for icon in icons {
    imageEntries.append("""
    {
      "filename" : "\(icon.filename)",
      "idiom" : "mac",
      "scale" : "\(icon.scale)",
      "size" : "\(icon.size)"
    }
    """)
}

let contentsJSON = """
{
  "images" : [
    \(imageEntries.joined(separator: ",\n    "))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

try! contentsJSON.write(
    toFile: "\(outputDir)/Contents.json",
    atomically: true,
    encoding: .utf8
)
print("wrote Contents.json")
