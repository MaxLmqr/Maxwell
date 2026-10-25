// Dessine l'icône MaxActivity (monogramme M en barres) et produit Resources/AppIcon.icns.
// Usage : swift Scripts/make-icon.swift
import AppKit

let background = NSColor(srgbRed: 0x23 / 255, green: 0x23 / 255, blue: 0x22 / 255, alpha: 1)
let light = NSColor(srgbRed: 0xF1 / 255, green: 0xEF / 255, blue: 0xE8 / 255, alpha: 1)
let mid = NSColor(srgbRed: 0xB4 / 255, green: 0xB2 / 255, blue: 0xA9 / 255, alpha: 1)
let accent = NSColor(srgbRed: 0x1D / 255, green: 0x9E / 255, blue: 0x75 / 255, alpha: 1)

/// Barres du M dans un repère 100 × 100, origine en haut à gauche.
let bars: [(x: CGFloat, top: CGFloat, color: NSColor)] = [
    (18, 22, light), (31.5, 38, mid), (45, 54, accent), (58.5, 38, mid), (72, 22, light),
]

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Grille macOS : le squircle occupe 824/1024 du canevas.
    let size = CGFloat(pixels)
    let inset = size * 100 / 1024
    let side = size - 2 * inset
    let unit = side / 100
    let squircle = NSRect(x: inset, y: inset, width: side, height: side)
    background.setFill()
    NSBezierPath(roundedRect: squircle, xRadius: 22.5 * unit, yRadius: 22.5 * unit).fill()

    for bar in bars {
        let height = (78 - bar.top) * unit
        let rect = NSRect(x: inset + bar.x * unit, y: inset + 22 * unit, width: 10 * unit, height: height)
        bar.color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4 * unit, yRadius: 4 * unit).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = drawIcon(pixels: points * scale).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
try drawIcon(pixels: 1024).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "✅ Resources/AppIcon.icns" : "❌ iconutil a échoué")
