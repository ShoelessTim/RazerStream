// Protocol constants ported from foxxyz/loupedeck constants.js and device.js

import Foundation

// MARK: - Device Identity

public enum RazerStreamController {
    public static let vendorID: UInt16 = 0x1532
    public static let productID: UInt16 = 0x0D06      // original (8 btns + touch + 6 knobs)
    public static let productIDX: UInt16 = 0x0D09     // X model (15 btns, no touch dial)

    /// Unified display space is 480×270: left knob strip (0–60), center
    /// touch grid (60–420), right knob strip (420–480). One display ID
    /// ("\x00M") covers all of it; coordinates select the region.
    public static let displayID: [UInt8] = [0x00, 0x4D]   // "\0M"
    public static let displayWidth: Int = 480
    public static let displayHeight: Int = 270
    public static let centerXOffset: Int = 60
    public static let centerWidth: Int = 360
    public static let buttonSize: Int = 90             // each touch tile is 90×90px
    public static let buttonColumns: Int = 4
    public static let buttonRows: Int = 3              // center grid is 4×3 = 12 tiles
    public static let buttonCount: Int = 12
    public static let knobCount: Int = 6
}

// MARK: - Protocol Commands

public enum Command: UInt8 {
    case buttonPress    = 0x00
    case knobRotate     = 0x01
    case setColor       = 0x02
    case serial         = 0x03
    case reset          = 0x06
    case version        = 0x07
    case setBrightness  = 0x09
    case mcu            = 0x0D
    case draw           = 0x0F
    case frameBuffer    = 0x10
    case setVibration   = 0x1B
    case touch          = 0x4D
    case touchCT        = 0x52
    case touchEnd       = 0x6D
    case touchEndCT     = 0x72
}

// MARK: - Display IDs

public enum DisplayID: UInt8 {
    case left   = 0x00
    case center = 0x01
    case right  = 0x02
    case knob   = 0x03
}

// MARK: - Knob IDs (as reported in rotation events)

public enum KnobID: UInt8, CaseIterable {
    case knob0 = 0x00
    case knob1 = 0x01
    case knob2 = 0x02
    case knob3 = 0x03
    case knob4 = 0x04
    case knob5 = 0x05
}

// MARK: - Haptic

public enum Haptic: UInt8 {
    case short      = 0x01
    case medium     = 0x0A
    case long       = 0x0F
    case veryLong   = 0x76
    case buzz       = 0x70
    case rumble1    = 0x77
    case rumble2    = 0x78
    case riseFall   = 0x6A
}

// MARK: - Serial / WebSocket Frame

enum WSOpcodes {
    static let binary: UInt8 = 0x82   // FIN=1, opcode=2 (binary frame)
}

// Max brightness level the device accepts
public let maxBrightness: UInt8 = 10
