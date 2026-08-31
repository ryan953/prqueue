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
    // Teal rather than the indigo the sibling apps use, so the two are still
    // told apart in a Dock at 32 points.
    let colors = [
        CGColor(red: 0.10, green: 0.72, blue: 0.60, alpha: 1),
        CGColor(red: 0.05, green: 0.44, blue: 0.55, alpha: 1),
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

    // The lanes: one row at full strength above rows that fade and shorten. That
    // is the whole idea of the app — a queue sorted so the top of it is the part
    // that wants you.
    let rowHeight = rect.height * 0.125
    let gap = rect.height * 0.062
    let left = rect.minX + rect.width * 0.17
    let right = rect.maxX - rect.width * 0.17
    let totalHeight = rowHeight * 4 + gap * 3
    var top = rect.midY + totalHeight / 2 - rowHeight

    let alphas: [CGFloat] = [1.0, 0.52, 0.36, 0.24]
    let widths: [CGFloat] = [1.0, 0.82, 0.64, 0.46]

    for row in 0..<4 {
        let bar = CGRect(
            x: left,
            y: top,
            width: (right - left) * widths[row],
            height: rowHeight
        )
        context.setFillColor(CGColor(gray: 1, alpha: alphas[row]))
        context.addPath(CGPath(
            roundedRect: bar,
            cornerWidth: rowHeight / 2,
            cornerHeight: rowHeight / 2,
            transform: nil
        ))
        context.fillPath()
        top -= rowHeight + gap
    }

    // A warm dot against the cool background, so the eye lands on the top lane
    // before it reads anything else.
    let dotRadius = rowHeight * 0.30
    let firstRowMidY = rect.midY + totalHeight / 2 - rowHeight / 2
    context.setFillColor(CGColor(red: 0.99, green: 0.74, blue: 0.18, alpha: 1))
    context.addEllipse(in: CGRect(
        x: left - dotRadius * 2.9,
        y: firstRowMidY - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    ))
    context.fillPath()

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
