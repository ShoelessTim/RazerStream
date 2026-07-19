import Foundation
import AppKit
import CoreGraphics
import RazerStreamKit

// Renders tile/knob configs into RGB565 buffers for the device display.

enum TileRenderer {

    // MARK: - Self-test patterns

    /// A vivid 90x90 test tile; per-index it draws gradients, crosshairs,
    /// corner markers, and the tile number so orientation, color depth, and
    /// edge alignment are all verifiable at a glance.
    static func renderTestTile(index: Int) -> Data {
        let size = RazerStreamController.buttonSize
        guard let ctx = makeContext(width: size, height: size) else {
            return Data(count: size * size * 2)
        }
        let s = CGFloat(size)

        // Background; each tile a different vivid hue so a wrong-position push
        // is obvious
        let hue = CGFloat(index) / 12.0
        ctx.setFillColor(NSColor(hue: hue, saturation: 0.85, brightness: 0.9, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

        switch index % 4 {
        case 0:
            // Horizontal RGB gradient bar
            for x in 0..<size {
                let f = CGFloat(x) / s
                ctx.setFillColor(NSColor(red: f, green: 1 - f, blue: 0.5, alpha: 1).cgColor)
                ctx.fill(CGRect(x: CGFloat(x), y: s * 0.35, width: 1, height: s * 0.3))
            }
        case 1:
            // Concentric rings; checks smooth curves
            for r in stride(from: s * 0.45, to: 4, by: -8) {
                ctx.setStrokeColor(NSColor(white: r.truncatingRemainder(dividingBy: 16) < 8 ? 1 : 0, alpha: 1).cgColor)
                ctx.setLineWidth(3)
                ctx.strokeEllipse(in: CGRect(x: s/2 - r, y: s/2 - r, width: r*2, height: r*2))
            }
        case 2:
            // Diagonal stripes
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
            ctx.setLineWidth(4)
            var x: CGFloat = -s
            while x < s {
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x + s, y: s))
                x += 14
            }
            ctx.strokePath()
        default:
            // Crosshair with center dot
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: s/2, y: 6)); ctx.addLine(to: CGPoint(x: s/2, y: s-6))
            ctx.move(to: CGPoint(x: 6, y: s/2)); ctx.addLine(to: CGPoint(x: s-6, y: s/2))
            ctx.strokePath()
        }

        // Corner markers; white dots verify all four edges reach the panel
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        for (cx, cy) in [(6, 6), (size-12, 6), (6, size-12), (size-12, size-12)] {
            ctx.fillEllipse(in: CGRect(x: CGFloat(cx), y: CGFloat(cy), width: 6, height: 6))
        }

        // Tile number, centered
        drawText("\(index)", in: ctx, canvas: size, fontSize: 22, yOffset: nil)

        return rgb565(from: ctx, width: size, height: size)
    }

    /// A 60x90 knob-strip test card; hue block plus its index.
    static func renderKnobTestZone(index: Int) -> Data {
        let w = 60, h = 90
        guard let ctx = makeContext(width: w, height: h) else {
            return Data(count: w * h * 2)
        }
        ctx.setFillColor(NSColor(hue: CGFloat(index) / 6.0, saturation: 0.9, brightness: 0.95, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(3)
        ctx.stroke(CGRect(x: 3, y: 3, width: w - 6, height: h - 6))
        drawText("K\(index + 1)", in: ctx, canvas: w, height: h, fontSize: 16, yOffset: nil)
        return rgb565(from: ctx, width: w, height: h)
    }

    // MARK: - Tiles (90×90)

    static func render(_ tile: TileConfig, toggledOn: Bool = false) -> Data {
        let size = RazerStreamController.buttonSize
        guard let ctx = makeContext(width: size, height: size) else {
            return Data(count: size * size * 2)
        }

        ctx.setFillColor(color(fromHex: tile.colorHex))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // Live content replaces the label/icon entirely; the background
        // color and toggle ring above/below still apply
        if tile.liveContent == .clock {
            drawClockFace(in: ctx, canvas: size)
            return rgb565(from: ctx, width: size, height: size)
        } else if tile.liveContent == .systemMeter {
            drawSystemMeter(in: ctx, canvas: size)
            return rgb565(from: ctx, width: size, height: size)
        } else if tile.liveContent == .diskSpace {
            drawDiskSpace(in: ctx, canvas: size, volumePath: tile.diskSpaceVolume)
            return rgb565(from: ctx, width: size, height: size)
        }

        // Toggles that are ON use the alternate icon when set
        let effectiveSymbol = (toggledOn && tile.altSymbol != nil) ? tile.altSymbol : tile.sfSymbol

        // Custom image beats SF symbol; both centered. Tinted images (mono
        // SVG pack icons) render white with symbol-style insets.
        if let stored = tile.imagePath,
           let path = IconPath.resolved(stored),
           let nsImage = NSImage(contentsOfFile: path) {
            if tile.iconTint {
                if let cgImage = tintedWhite(nsImage)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    drawFitted(cgImage, in: ctx, canvas: size, inset: 18)
                }
            } else if let cgImage = normalizedImage(nsImage).cgImage(forProposedRect: nil, context: nil, hints: nil) {
                drawFitted(cgImage, in: ctx, canvas: size, inset: 0)
            }
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

        if knob.liveContent == .clock {
            drawCompactClockFace(in: ctx, width: w, height: h)
            return rgb565(from: ctx, width: w, height: h)
        } else if knob.liveContent == .systemMeter {
            drawCompactSystemMeter(in: ctx, width: w, height: h)
            return rgb565(from: ctx, width: w, height: h)
        } else if knob.liveContent == .diskSpace {
            drawCompactDiskSpace(in: ctx, width: w, height: h, volumePath: knob.diskSpaceVolume)
            return rgb565(from: ctx, width: w, height: h)
        }

        // Center the icon and label as one vertical group; icon alone sits
        // dead center, label alone sits dead center, both stack around center
        let hasLabel = !knob.label.isEmpty
        let labelBlock: CGFloat = hasLabel ? 18 : 0   // text height plus gap

        // Custom image (from an icon pack or user file) beats an SF Symbol,
        // same precedence as tiles. Tinted images render white.
        var iconImage: CGImage?
        if let stored = knob.imagePath,
           let path = IconPath.resolved(stored),
           let nsImage = NSImage(contentsOfFile: path) {
            if knob.iconTint {
                iconImage = tintedWhite(nsImage)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            } else {
                iconImage = normalizedImage(nsImage).cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
        } else if let symbol = knob.sfSymbol {
            iconImage = symbolImage(symbol, pointSize: 26)
        }

        if let cgImage = iconImage {
            let iw = CGFloat(cgImage.width), ih = CGFloat(cgImage.height)
            let scale = min(36 / iw, 36 / ih, 1)
            let dw = iw * scale, dh = ih * scale
            let groupH = dh + labelBlock
            // CG origin is bottom left; the icon occupies the top of the group
            let iconY = (CGFloat(h) - groupH) / 2 + labelBlock
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: (CGFloat(w) - dw) / 2,
                                         y: iconY,
                                         width: dw, height: dh))
            if hasLabel {
                drawText(knob.label, in: ctx, canvas: w, height: h,
                         fontSize: 10, yOffset: iconY - labelBlock + 2)
            }
        } else if hasLabel {
            drawText(knob.label, in: ctx, canvas: w, height: h,
                     fontSize: 10, yOffset: nil)
        }

        return rgb565(from: ctx, width: w, height: h)
    }

    /// A smaller clock face sized for the 60-wide knob strip; time only,
    /// the full date does not fit legibly at this width.
    private static func drawCompactClockFace(in ctx: CGContext, width: Int, height: Int) {
        drawText(clockTimeFormatter.string(from: Date()), in: ctx, canvas: width, height: height,
                 fontSize: 13, yOffset: CGFloat(height) * 0.44)
        drawText(clockDateFormatter.string(from: Date()), in: ctx, canvas: width, height: height,
                 fontSize: 9, yOffset: CGFloat(height) * 0.30)
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

    /// Re-rasterizes any loaded image (PNG or SVG) into a fixed 256pt
    /// canvas, preserving aspect ratio. Needed before any fit-to-size math
    /// runs: `NSImage(contentsOfFile:)` on an SVG with only a `viewBox`
    /// (no explicit `width`/`height` attributes) can resolve `.size` to an
    /// AppKit-internal default far larger than the actual artwork, and
    /// `cgImage(forProposedRect: nil, ...)` then hands back a CGImage at
    /// that inflated size. `drawFitted`/the knob icon scale both trust the
    /// CGImage's raw width/height, so an inflated size makes the icon
    /// render far smaller than intended, worse on knobs (smaller target
    /// size) than tiles — exactly the reported symptom, and one that never
    /// hits PNGs, since a PNG's pixel size is never ambiguous. Rasterizing
    /// here first pins every image to the same known, correct target size
    /// before that math ever runs.
    private static func normalizedImage(_ image: NSImage) -> NSImage {
        let target: CGFloat = 256
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let size = aspect >= 1
            ? NSSize(width: target, height: target / aspect)
            : NSSize(width: target * aspect, height: target)
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    /// Recolors a mono image (like a stroke SVG icon) to solid white,
    /// preserving its alpha. Rasterizes at high resolution so small vector
    /// icons (Lucide is 24x24) stay crisp when scaled onto a tile.
    private static func tintedWhite(_ image: NSImage) -> NSImage? {
        let normalized = normalizedImage(image)
        let out = NSImage(size: normalized.size, flipped: false) { rect in
            normalized.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return out
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

    private static let clockTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j:mm")   // respects 12/24h locale setting
        return f
    }()

    private static let clockDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d")  // e.g. "Tue 15"
        return f
    }()

    /// Draws the current time large, centered, with the weekday and day
    /// underneath; used for tiles with liveContent set to .clock.
    private static func drawClockFace(in ctx: CGContext, canvas: Int) {
        let now = Date()
        drawText(clockTimeFormatter.string(from: now), in: ctx, canvas: canvas,
                 fontSize: 22, yOffset: CGFloat(canvas) * 0.42)
        drawText(clockDateFormatter.string(from: now), in: ctx, canvas: canvas,
                 fontSize: 12, yOffset: CGFloat(canvas) * 0.20)
    }

    /// Two labeled usage bars (CPU above RAM), sized for a 90x90 tile.
    private static func drawSystemMeter(in ctx: CGContext, canvas: Int) {
        let cpu = SystemMeter.cpuUsage()
        let ram = SystemMeter.memoryUsage()
        let s = CGFloat(canvas)
        let barWidth = s - 24
        let barX = (s - barWidth) / 2
        let barHeight: CGFloat = 12

        drawText("CPU \(Int(cpu * 100))%", in: ctx, canvas: canvas, fontSize: 11, yOffset: s * 0.62)
        drawMeterBar(fraction: cpu, in: ctx, x: barX, y: s * 0.50, width: barWidth, height: barHeight)

        drawText("RAM \(Int(ram * 100))%", in: ctx, canvas: canvas, fontSize: 11, yOffset: s * 0.28)
        drawMeterBar(fraction: ram, in: ctx, x: barX, y: s * 0.16, width: barWidth, height: barHeight)
    }

    /// Two small pie charts, sized for the 60-wide knob strip: CPU above,
    /// RAM below, each with its percentage underneath. A bar doesn't have
    /// room to read as a bar at this width; a pie reads at a glance.
    private static func drawCompactSystemMeter(in ctx: CGContext, width: Int, height: Int) {
        let cpu = SystemMeter.cpuUsage()
        let ram = SystemMeter.memoryUsage()
        let w = CGFloat(width), h = CGFloat(height)

        drawPieChart(fraction: cpu, in: ctx, center: CGPoint(x: w / 2, y: h * 0.78), radius: 13)
        drawText("CPU \(Int(cpu * 100))%", in: ctx, canvas: width, height: height,
                 fontSize: 9, yOffset: h * 0.56)

        drawPieChart(fraction: ram, in: ctx, center: CGPoint(x: w / 2, y: h * 0.34), radius: 13)
        drawText("RAM \(Int(ram * 100))%", in: ctx, canvas: width, height: height,
                 fontSize: 9, yOffset: h * 0.12)
    }

    /// Fills clockwise from 12 o'clock as `fraction` rises from 0 to 1; red
    /// past 85%, matching the danger convention the usage bars already use.
    private static func drawPieChart(fraction: Double, in ctx: CGContext, center: CGPoint, radius: CGFloat) {
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.15))
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

        let clamped = max(0, min(1, fraction))
        guard clamped > 0 else { return }

        ctx.setFillColor(clamped > 0.85
            ? CGColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1)
            : CGColor(red: 0.3, green: 0.85, blue: 0.5, alpha: 1))

        let steps = 60
        let sweepSteps = max(1, Int(Double(steps) * clamped))
        ctx.move(to: center)
        for i in 0...sweepSteps {
            let t = Double(i) / Double(steps)
            let angle = CGFloat.pi / 2 - CGFloat(t) * 2 * .pi   // start at 12 o'clock, sweep clockwise
            ctx.addLine(to: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
        }
        ctx.closePath()
        ctx.fillPath()
    }

    /// A single usage bar (fills with how much is USED, so it reads red
    /// when space is running low, same danger convention as the CPU/RAM
    /// bars) plus the actual free amount as text, since "how much is free"
    /// is what was actually asked for, not just a percentage.
    private static func drawDiskSpace(in ctx: CGContext, canvas: Int, volumePath: String) {
        let s = CGFloat(canvas)
        guard let reading = DiskSpaceMeter.reading(forVolumeAt: volumePath) else {
            drawText("No Data", in: ctx, canvas: canvas, fontSize: 12, yOffset: nil)
            return
        }
        let barWidth = s - 24
        let barX = (s - barWidth) / 2

        drawText("DISK", in: ctx, canvas: canvas, fontSize: 11, yOffset: s * 0.62)
        drawMeterBar(fraction: reading.usedFraction, in: ctx, x: barX, y: s * 0.50, width: barWidth, height: 12)
        drawText(DiskSpaceMeter.formattedFree(reading.freeBytes), in: ctx, canvas: canvas,
                  fontSize: 11, yOffset: s * 0.28)
    }

    /// A pie chart (used fraction) above the free-space amount, sized for
    /// the 60-wide knob strip, same style as the CPU/RAM pies.
    private static func drawCompactDiskSpace(in ctx: CGContext, width: Int, height: Int, volumePath: String) {
        guard let reading = DiskSpaceMeter.reading(forVolumeAt: volumePath) else {
            drawText("No Data", in: ctx, canvas: width, height: height, fontSize: 10, yOffset: nil)
            return
        }
        let w = CGFloat(width), h = CGFloat(height)
        drawPieChart(fraction: reading.usedFraction, in: ctx, center: CGPoint(x: w / 2, y: h * 0.60), radius: 16)
        drawText(DiskSpaceMeter.formattedFree(reading.freeBytes), in: ctx, canvas: width, height: height,
                  fontSize: 9, yOffset: h * 0.16)
    }

    private static func drawMeterBar(fraction: Double, in ctx: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let clamped = max(0, min(1, fraction))
        let track = CGRect(x: x, y: y, width: width, height: height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.15))
        ctx.fill(track)
        ctx.setFillColor(clamped > 0.85
            ? CGColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1)
            : CGColor(red: 0.3, green: 0.85, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: x, y: y, width: width * clamped, height: height))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.4))
        ctx.setLineWidth(1)
        ctx.stroke(track)
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
