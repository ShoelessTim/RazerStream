import Foundation

// MARK: - Commands sent to the device

public enum DeviceCommand {
    case setBrightness(UInt8)                          // 0–10
    case setButtonColor(button: Int, r: UInt8, g: UInt8, b: UInt8)
    case setButtonImage(button: Int, rgb565: Data)     // 90×90 px RGB565
    case setDisplayImage(display: DisplayID, x: Int, y: Int, w: Int, h: Int, rgb565: Data)
    case vibrate(Haptic)
    case requestVersion
    case requestSerial
    case reset
}

// MARK: - Serialization to protocol bytes (payload only, not the WS frame wrapper)

extension DeviceCommand {
    /// Returns (command byte, payload bytes) for the protocol frame.
    func encode() -> (Command, Data) {
        switch self {

        case .setBrightness(let level):
            // Payload is a single byte 0–10. (A leading 0x00 gets read as
            // "brightness zero" and blanks the panel.)
            let clamped = min(level, maxBrightness)
            return (.setBrightness, Data([clamped]))

        case .setButtonColor(let btn, let r, let g, let b):
            // SET_COLOR payload: [buttonID, r, g, b]
            return (.setColor, Data([UInt8(btn), r, g, b]))

        case .setButtonImage(let button, let rgb565):
            // Buttons live on the center touch area, which starts at x=60 in
            // the unified 480×270 coordinate space (left knob strip is 0–60).
            let col = button % RazerStreamController.buttonColumns
            let row = button / RazerStreamController.buttonColumns
            let x = RazerStreamController.centerXOffset + col * RazerStreamController.buttonSize
            let y = row * RazerStreamController.buttonSize
            let w = RazerStreamController.buttonSize
            let h = RazerStreamController.buttonSize
            return (.frameBuffer, Self.imagePayload(
                x: x, y: y, w: w, h: h,
                rgb565: rgb565
            ))

        case .setDisplayImage(_, let x, let y, let w, let h, let rgb565):
            return (.frameBuffer, Self.imagePayload(
                x: x, y: y, w: w, h: h,
                rgb565: rgb565
            ))

        case .vibrate(let haptic):
            return (.setVibration, Data([haptic.rawValue]))

        case .requestVersion:
            return (.version, Data())

        case .requestSerial:
            return (.serial, Data())

        case .reset:
            return (.reset, Data())
        }
    }

    // MARK: - Private helpers

    private static func imagePayload(
        x: Int, y: Int, w: Int, h: Int,
        rgb565: Data
    ) -> Data {
        // [display ID "\x00M" (2 bytes), x(2 BE), y(2 BE), w(2 BE), h(2 BE), pixels LE]
        var payload = Data(capacity: 2 + 8 + rgb565.count)
        payload.append(contentsOf: RazerStreamController.displayID)
        payload.appendUInt16BE(UInt16(x))
        payload.appendUInt16BE(UInt16(y))
        payload.appendUInt16BE(UInt16(w))
        payload.appendUInt16BE(UInt16(h))
        payload.append(rgb565)
        return payload
    }
}

// MARK: - Data helpers

extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    func readUInt16BE(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }
}
