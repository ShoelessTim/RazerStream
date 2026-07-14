import Foundation
import AppKit
import CoreGraphics
import RazerStreamKit

// Renders a TileConfig into a 90×90 RGB565 buffer for the device display.

enum TileRenderer {

    static func render(_ tile: TileConfig) -> Data {
        let size = RazerStreamController.buttonSize
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data(count: size * size * 2) }

        // Background
        let bg = color(fromHex: tile.colorHex)
        ctx.setFillColor(bg)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // Image (aspect-fit, centered) — drawn over the background
        if let path = tile.imagePath,
           let nsImage = NSImage(contentsOfFile: path),
           let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let iw = CGFloat(cgImage.width), ih = CGFloat(cgImage.height)
            let scale = min(CGFloat(size) / iw, CGFloat(size) / ih)
            let w = iw * scale, h = ih * scale
            let rect = CGRect(x: (CGFloat(size) - w) / 2,
                              y: (CGFloat(size) - h) / 2,
                              width: w, height: h)
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: rect)
        }

        // Label text (centered)
        if !tile.label.isEmpty {
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx

            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 16),
                .foregroundColor: NSColor.white,
                .paragraphStyle: para,
            ]
            let str = NSAttributedString(string: tile.label, attributes: attrs)
            let bounds = str.boundingRect(
                with: CGSize(width: CGFloat(size - 8), height: CGFloat(size)),
                options: [.usesLineFragmentOrigin]
            )
            str.draw(in: CGRect(
                x: 4,
                y: (CGFloat(size) - bounds.height) / 2,
                width: CGFloat(size - 8),
                height: bounds.height
            ))
            NSGraphicsContext.restoreGraphicsState()
        }

        // Convert RGBA8888 → RGB565 little-endian.
        // CGContext memory is already top-row-first — no flipping. (Reversing
        // rows here shows up as 180°-rotated tiles on the device.)
        guard let pixels = ctx.data else { return Data(count: size * size * 2) }
        var out = Data(capacity: size * size * 2)
        let buf = pixels.bindMemory(to: UInt8.self, capacity: size * size * 4)
        for row in 0..<size {
            for col in 0..<size {
                let i = (row * size + col) * 4
                let r = buf[i], g = buf[i + 1], b = buf[i + 2]
                let v: UInt16 = (UInt16(r & 0xF8) << 8) | (UInt16(g & 0xFC) << 3) | UInt16(b >> 3)
                out.append(UInt8(v & 0xFF))
                out.append(UInt8(v >> 8))
            }
        }
        return out
    }

    /// Renders a 60×90 test card for a knob zone: distinct shape + index.
    /// Knobs 0–2 = left strip top→bottom, 3–5 = right strip top→bottom.
    static func renderKnobZone(index: Int) -> Data {
        let w = 60, h = 90
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data(count: w * h * 2) }

        let hues: [CGColor] = [
            CGColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1),
            CGColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1),
            CGColor(red: 0.3, green: 0.5, blue: 0.95, alpha: 1),
        ]
        let hue = hues[index % 3]

        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(hue)

        // Shape per row: 0=circle, 1=triangle, 2=square
        let cx = CGFloat(w) / 2, cy = CGFloat(h) / 2, r: CGFloat = 20
        switch index % 3 {
        case 0:
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        case 1:
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx, y: cy + r))
            ctx.addLine(to: CGPoint(x: cx - r, y: cy - r))
            ctx.addLine(to: CGPoint(x: cx + r, y: cy - r))
            ctx.closePath()
            ctx.fillPath()
        default:
            ctx.fill(CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }

        // Index digit in the corner
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        NSAttributedString(string: "\(index)", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
        ]).draw(at: CGPoint(x: 4, y: 4))
        NSGraphicsContext.restoreGraphicsState()

        guard let pixels = ctx.data else { return Data(count: w * h * 2) }
        var out = Data(capacity: w * h * 2)
        let buf = pixels.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for row in 0..<h {
            for col in 0..<w {
                let i = (row * w + col) * 4
                let v: UInt16 = (UInt16(buf[i] & 0xF8) << 8)
                              | (UInt16(buf[i + 1] & 0xFC) << 3)
                              | UInt16(buf[i + 2] >> 3)
                out.append(UInt8(v & 0xFF))
                out.append(UInt8(v >> 8))
            }
        }
        return out
    }

    private static func color(fromHex hex: String) -> CGColor {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        return CGColor(red: r, green: g, blue: b, alpha: 1)
    }
}
