import Foundation

// A device-wide preference (not per-profile content, same reasoning as
// HapticFeedback): which physical direction counts as "increase" for a
// knob assigned to Volume or Brightness rotation. One switch instead of
// hand-configuring clockwise/counterclockwise separately on every knob.
enum KnobDirection {
    private static let key = "knobClockwiseIncreases"

    /// true: turning right (clockwise) increases, left decreases.
    /// false: the reverse. Defaults to true (right = positive).
    static var clockwiseIncreases: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// Simplifies knob rotation configuration: instead of picking an arbitrary
// action for clockwise and another for counterclockwise, Volume and
// Brightness are single choices whose direction is derived from
// KnobDirection.clockwiseIncreases. "Custom" is the escape hatch for
// anything else (page navigation, arbitrary actions per direction).
enum KnobRotationMode: Equatable {
    case none
    case volume
    case brightness
    case custom

    static func detect(clockwise: ControlAction, counterClockwise: ControlAction) -> KnobRotationMode {
        if clockwise == .none && counterClockwise == .none { return .none }
        if isPair(clockwise, counterClockwise, .volumeUp, .volumeDown) { return .volume }
        if isPair(clockwise, counterClockwise, .brightnessUp, .brightnessDown) { return .brightness }
        return .custom
    }

    static func actions(for mode: KnobRotationMode, clockwiseIncreases: Bool) -> (clockwise: ControlAction, counterClockwise: ControlAction) {
        switch mode {
        case .none:
            return (.none, .none)
        case .volume:
            return clockwiseIncreases ? (.volumeUp, .volumeDown) : (.volumeDown, .volumeUp)
        case .brightness:
            return clockwiseIncreases ? (.brightnessUp, .brightnessDown) : (.brightnessDown, .brightnessUp)
        case .custom:
            return (.none, .none)   // caller should leave existing fields alone in this case
        }
    }

    private static func isPair(_ a: ControlAction, _ b: ControlAction, _ up: ControlAction, _ down: ControlAction) -> Bool {
        (a == up && b == down) || (a == down && b == up)
    }
}
