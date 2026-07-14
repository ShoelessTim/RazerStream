import Foundation
import AppKit
import CoreGraphics
import RazerStreamKit

// Renders tile/knob configs into RGB565 buffers for the device display.

enum TileRenderer {

    // MARK: - Tiles (90×90)

    static func render(_ tile: TileConfig, toggledOn: Bool = false) -> Data {
        let size = RazerStreamController.buttonSize
        guard let ctx = makeContext(width: size, height: size) else {
            return Data(count: size * size * 2)
        }

        ctx.setFillColor(color(fromHex: tile.colorHex))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // Toggles that are ON use the alternate icon when set
        let effectiveSymbol = (toggledOn && tile.altSymbol != nil) ? tile.altSymbol : tile.sfSymbol

        // Custom image beats SF symbol; both centered
        if let path = tile.imagePath,
           let nsImage = NSImage(contentsOfFile: path),
           let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            drawFitted(cgImage, in: ctx, canvas: size, inset: 0)
        } else if let symbol = effectiveSymbol,
                  let cgImage = symbolImage(symbol, pointSize: 44) {
            drawFitted(cgImage, in: ctx, canvas: size, inset: 18)
        }

        if !tile.label.isEmpty {
            // Label sits at the bottom when there's an icon, centered otherwise
            let hasIcon = tile.imagePath != nil || effectiveSymbol != nil
            drawText(tile.label, in: ctx, canvas: size,
                     fontSize: hasIcon ? 12 : 16,
                     yOffset: hasIcon ? 6 : nil)
        }

        // ON-state ring for toggle tiles
        if toggledOn {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.setLineWidth(4)
            ctx.stroke(CGRect(x: 2, y: 2, width: size - 4, height: size - 4))
        }

        return rgb565(from: ctx, width: size, height: size)
    }

    // MARK: - Knob zones (60×90)

    static func renderKnobZone(_ knob: KnobConfig, index: Int) -> Data {
        let w = 60, h = 90
        guard let ctx = makeContext(width: w, height: h) else {
            return Data(count: w * h * 2)
        }

        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        if let symbol = knob.sfSymbol, let cgImage = symbolImage(symbol, pointSize: 26) {
            let iw = CGFloat(cgImage.width), ih = CGFloat(cgImage.height)
            let scale = min(36 / iw, 36 / ih, 1)
            let dw = iw * scale, dh = ih * scale
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: (CGFloat(w) - dw) / 2,
                                         y: CGFloat(h) - dh - 12,
                                         width: dw, height: dh))
        }

        if !knob.label.isEmpty {
            drawText(knob.label, in: ctx, canvas: w, height: h, fontSize: 10, yOffset: 8)
        }

        return rgb565(from: ctx, width: w, height: h)
    }

    // MARK: - Shared drawing helpers

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// White template rendering of an SF Symbol.
    private static func symbolImage(_ name: String, pointSize: CGFloat) -> CGImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(.init(paletteColors: [.white]))
        guard let configured = base.withSymbolConfiguration(config) else { return nil }
        return configured.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func drawFitted(_ image: CGImage, in ctx: CGContext, canvas: Int, inset: CGFloat) {
        let avail = CGFloat(canvas) - inset * 2
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let scale = min(avail / iw, avail / ih)
        let w = iw * scale, h = ih * scale
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: (CGFloat(canvas) - w) / 2,
                                   y: (CGFloat(canvas) - h) / 2,
                                   width: w, height: h))
    }

    private static func drawText(
        _ text: String, in ctx: CGContext, canvas: Int, height: Int? = nil,
        fontSize: CGFloat, yOffset: CGFloat?
    ) {
        let h = height ?? canvas
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let str = NSAttributedString(string: text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ])
        let bounds = str.boundingRect(
            with: CGSize(width: CGFloat(canvas - 6), height: CGFloat(h)),
            options: [.usesLineFragmentOrigin]
        )
        let y = yOffset ?? (CGFloat(h) - bounds.height) / 2
        str.draw(in: CGRect(x: 3, y: y, width: CGFloat(canvas - 6), height: bounds.height))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// RGBA8888 → RGB565 LE. CGContext memory is top-row-first; no flipping.
    private static func rgb565(from ctx: CGContext, width: Int, height: Int) -> Data {
        guard let pixels = ctx.data else { return Data(count: width * height * 2) }
        var out = Data(capacity: width * height * 2)
        let buf = pixels.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for row in 0..<height {
            for col in 0..<width {
                let i = (row * width + col) * 4
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
        return CGColor(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}
