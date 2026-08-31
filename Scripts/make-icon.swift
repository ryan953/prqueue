// Draws the app icon and writes an .icns. Run by Scripts/bundle.sh.
//
// Generating the icon keeps binary assets out of the repository: the only source of
// truth for the artwork is this file.
import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.icns"

/// Draw one square icon at `size` points.
func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // macOS icons sit in a rounded square inset from the canvas edge.
    let inset = s * 0.086
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = CGPath(
        roundedRect: rect,
        cornerWidth: rect.width * 0.2237,
        cornerHeight: rect.height * 0.2237,
        transform: nil
    )

    context.saveGState()
    context.addPath(squircle)
    context.clip()
    // Dark slate, so the added and removed rows are the only saturated things in
    // the square and the icon stays apart from the indigo sibling apps.
    let colors = [
        CGColor(red: 0.25, green: 0.31, blue: 0.44, alpha: 1),
        CGColor(red: 0.10, green: 0.13, blue: 0.21, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }
    context.restoreGState()

    // A diff: one row added, one removed, between two untouched ones. Green and
    // red carry the meaning, so it still reads once the + and - stop resolving
    // at the smallest sizes.
    let rowHeight = rect.height * 0.132
    let gap = rect.height * 0.055
    let left = rect.minX + rect.width * 0.14
    let span = rect.maxX - rect.width * 0.14 - left
    let totalHeight = rowHeight * 4 + gap * 3
    var top = rect.midY + totalHeight / 2 - rowHeight

    let unchanged = CGColor(gray: 1, alpha: 0.32)
    let rows: [(color: CGColor, width: CGFloat, sign: Int)] = [
        (unchanged, 0.60, 0),
        (CGColor(red: 0.24, green: 0.80, blue: 0.44, alpha: 1), 0.96, 1),
        (CGColor(red: 0.98, green: 0.36, blue: 0.40, alpha: 1), 0.76, -1),
        (unchanged, 0.48, 0),
    ]

    for row in rows {
        let bar = CGRect(x: left, y: top, width: span * row.width, height: rowHeight)
        context.setFillColor(row.color)
        context.addPath(CGPath(
            roundedRect: bar,
            cornerWidth: rowHeight / 2,
            cornerHeight: rowHeight / 2,
            transform: nil
        ))
        context.fillPath()

        if row.sign != 0 {
            let centreX = bar.minX + rowHeight * 0.62
            let arm = rowHeight * 0.26
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.96))
            context.setLineWidth(s * 0.026)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: centreX - arm, y: bar.midY))
            context.addLine(to: CGPoint(x: centreX + arm, y: bar.midY))
            if row.sign > 0 {
                context.move(to: CGPoint(x: centreX, y: bar.midY - arm))
                context.addLine(to: CGPoint(x: centreX, y: bar.midY + arm))
            }
            context.strokePath()
        }

        top -= rowHeight + gap
    }

    return context.makeImage()
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("PRQueue-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

// The set of sizes iconutil expects.
let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard
        let image = render(size: variant.size),
        let destination = CGImageDestinationCreateWithURL(
            iconset.appendingPathComponent("\(variant.name).png") as CFURL,
            "public.png" as CFString,
            1,
            nil
        )
    else {
        FileHandle.standardError.write(Data("Failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputPath]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
