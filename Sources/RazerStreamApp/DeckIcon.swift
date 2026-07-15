import AppKit
import SwiftUI

// Tiny menu-bar rendering of the Stream Controller: rounded body,
// 4×3 tile grid, knob nubs on each side. Template image so macOS
// tints it correctly for light/dark menu bars.

@MainActor
enum DeckIcon {

    static let menuBar: NSImage = {
        let size = NSSize(width: 22, height: 15)
        let image = NSImage(size: size, flipped: false) { _ in
            let body = NSBezierPath(
                roundedRect: NSRect(x: 3, y: 1.5, width: 16, height: 12),
                xRadius: 2.5, yRadius: 2.5
            )
            body.lineWidth = 1.2
            NSColor.black.setStroke()
            body.stroke()

            // Knob nubs poking out of the sides
            for y: CGFloat in [3.5, 7, 10.5] {
                let left = NSBezierPath(
                    ovalIn: NSRect(x: 0.8, y: y - 1, width: 2, height: 2))
                let right = NSBezierPath(
                    ovalIn: NSRect(x: 19.2, y: y - 1, width: 2, height: 2))
                NSColor.black.setFill()
                left.fill()
                right.fill()
            }

            // 4×3 tile grid
            NSColor.black.setFill()
            for row in 0..<3 {
                for col in 0..<4 {
                    let tile = NSRect(
                        x: 5.2 + CGFloat(col) * 3.2,
                        y: 3.4 + CGFloat(row) * 3.0,
                        width: 2.2, height: 2.0
                    )
                    NSBezierPath(roundedRect: tile, xRadius: 0.5, yRadius: 0.5).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
