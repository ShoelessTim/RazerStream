#!/usr/bin/env swift
// Generates AppIcon.iconset PNGs; a colorful render of the deck itself.
// Run by make_app.sh; output goes to dist/AppIcon.iconset for iconutil.

import AppKit

let tileColors = ["8E3B46", "B36A2E", "8F8A2B", "3E7C4F",
                  "2E7C8F", "31518F", "6C3E8F", "8F2E6E",
                  "4A4E69", "22577A", "38A3A5", "57CC99"]

func color(_ hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&v)
    return NSColor(
        red: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1
    )
}

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let s = size / 1024

        // Rounded background plate; macOS-style squircle-ish
        let plate = NSBezierPath(
            roundedRect: NSRect(x: 60 * s, y: 60 * s, width: 904 * s, height: 904 * s),
            xRadius: 200 * s, yRadius: 200 * s
        )
        NSColor(white: 0.11, alpha: 1).setFill()
        plate.fill()

        // Device body; slightly lighter rounded rect
        let body = NSBezierPath(
            roundedRect: NSRect(x: 150 * s, y: 220 * s, width: 724 * s, height: 584 * s),
            xRadius: 70 * s, yRadius: 70 * s
        )
        NSColor(white: 0.17, alpha: 1).setFill()
        body.fill()

        // Knob nubs; three per side
        NSColor(white: 0.30, alpha: 1).setFill()
        for row in 0..<3 {
            let y = (300 + CGFloat(row) * 180) * s
            NSBezierPath(ovalIn: NSRect(x: 108 * s, y: y, width: 84 * s, height: 84 * s)).fill()
            NSBezierPath(ovalIn: NSRect(x: 832 * s, y: y, width: 84 * s, height: 84 * s)).fill()
        }

        // 4x3 colorful tile grid
        let tileSize = 130 * s
        let gap = 24 * s
        let gridW = 4 * tileSize + 3 * gap
        let startX = (size - gridW) / 2
        let startY = 292 * s
        for row in 0..<3 {
            for col in 0..<4 {
                let idx = row * 4 + col
                let x = startX + CGFloat(col) * (tileSize + gap)
                let y = startY + CGFloat(2 - row) * (tileSize + gap)
                color(tileColors[idx]).setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: y, width: tileSize, height: tileSize),
                    xRadius: 26 * s, yRadius: 26 * s
                ).fill()
            }
        }

        // Status light; the little green dot of life
        color("57CC99").setFill()
        NSBezierPath(ovalIn: NSRect(x: 196 * s, y: 236 * s, width: 36 * s, height: 36 * s)).fill()

        return true
    }
}

func writePNG(_ image: NSImage, to path: String, pixels: Int) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// iconutil requires this exact naming scheme
let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, px) in specs {
    let img = drawIcon(size: px)
    writePNG(img, to: "\(outDir)/\(name)", pixels: Int(px))
}
print("iconset written to \(outDir)")
