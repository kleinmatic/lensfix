#!/usr/bin/env swift
// Generates Lensfix's app icon (.icns) with no external assets.
// Usage: swift make-icon.swift /path/to/output/AppIcon.icns
import AppKit

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.icns"

/// Draw the icon at a given pixel size into a PNG.
func renderPNG(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let side = CGFloat(pixels)
    let inset = side * 0.06
    let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let corner = rect.width * 0.22
    let bg = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

    // Vertical gradient background (deep slate → indigo).
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.28, alpha: 1),
        NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.17, alpha: 1),
    ])
    gradient?.draw(in: bg, angle: -90)

    // Aperture symbol, centered and white.
    let symbolSide = rect.width * 0.62
    let symbolRect = NSRect(
        x: rect.midX - symbolSide / 2,
        y: rect.midY - symbolSide / 2,
        width: symbolSide, height: symbolSide)

    if let symbol = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: symbolSide, weight: .regular)
        let sized = symbol.withSymbolConfiguration(config) ?? symbol
        // Tint the template symbol white on its OWN transparent canvas, so
        // sourceAtop only paints the glyph's shape (not the whole rect).
        let white = NSImage(size: sized.size)
        white.lockFocus()
        sized.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.white.set()
        NSRect(origin: .zero, size: sized.size).fill(using: .sourceAtop)
        white.unlockFocus()
        white.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    } else {
        // Fallback: concentric lens rings if the SF Symbol is unavailable.
        NSColor.white.set()
        let outer = NSBezierPath(ovalIn: symbolRect)
        outer.lineWidth = symbolSide * 0.08
        outer.stroke()
        let innerSide = symbolSide * 0.4
        let inner = NSBezierPath(ovalIn: NSRect(
            x: rect.midX - innerSide / 2, y: rect.midY - innerSide / 2,
            width: innerSide, height: innerSide))
        inner.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// Standard iconset sizes: (name, pixels).
let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
let tmp = NSTemporaryDirectory() + "Lensfix.iconset"
try? fm.removeItem(atPath: tmp)
try! fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)

for (name, px) in entries {
    guard let data = renderPNG(pixels: px) else {
        FileHandle.standardError.write("Failed to render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: "\(tmp)/\(name).png"))
}

// Convert the iconset to .icns via iconutil.
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", tmp, "-o", outPath]
try! proc.run()
proc.waitUntilExit()
try? fm.removeItem(atPath: tmp)

if proc.terminationStatus == 0 {
    print("Wrote \(outPath)")
} else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
