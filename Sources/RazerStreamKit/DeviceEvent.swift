import Foundation

// MARK: - Events emitted by the device

public enum DeviceEvent: Sendable {
    case buttonPress(id: Int, pressed: Bool)
    case knobRotate(id: Int, delta: Int)
    case touchStart(x: Int, y: Int, touchID: Int)
    case touchMove(x: Int, y: Int, touchID: Int)
    case touchEnd(x: Int, y: Int, touchID: Int)
    case connected
    case disconnected(reason: String)
    case firmwareVersion(String)
    case serialNumber(String)
    case error(Swift.Error)
}

extension DeviceEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .buttonPress(let id, let pressed):
            return "Button \(id) \(pressed ? "pressed" : "released")"
        case .knobRotate(let id, let delta):
            return "Knob \(id) \(delta > 0 ? "+\(delta)" : "\(delta)")"
        case .touchStart(let x, let y, let tid):
            return "Touch start  (\(x), \(y))  id=\(tid)"
        case .touchMove(let x, let y, let tid):
            return "Touch move   (\(x), \(y))  id=\(tid)"
        case .touchEnd(let x, let y, let tid):
            return "Touch end    (\(x), \(y))  id=\(tid)"
        case .connected:
            return "Device connected"
        case .disconnected(let reason):
            return "Device disconnected: \(reason)"
        case .firmwareVersion(let v):
            return "Firmware: \(v)"
        case .serialNumber(let s):
            return "Serial: \(s)"
        case .error(let e):
            return "Error: \(e)"
        }
    }
}

// MARK: - Button → grid coordinate helpers

public extension DeviceEvent {
    /// Returns (col, row) for a button ID in the 4×2 grid, if applicable.
    static func gridPosition(forButton id: Int) -> (col: Int, row: Int)? {
        guard id >= 0 && id < RazerStreamController.buttonCount else { return nil }
        return (col: id % RazerStreamController.buttonColumns,
                row: id / RazerStreamController.buttonColumns)
    }
}
