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

        // Convert RGBA8888 → RGB565 little-endian
        guard let pixels = ctx.data else { return Data(count: size * size * 2) }
        var out = Data(capacity: size * size * 2)
        let buf = pixels.bindMemory(to: UInt8.self, capacity: size * size * 4)
        // CGContext origin is bottom-left; device expects top-left row order
        for row in stride(from: size - 1, through: 0, by: -1) {
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
