import Foundation
import RazerStreamKit

// A device-wide preference (not per-profile content, so UserDefaults rather
// than the JSON profile), same pattern as LaunchAtLogin: whether the deck
// buzzes on a physical press, and which pattern to use. The device already
// exposes a vibrate command (RazerStreamKit's Haptic enum); this just wires
// a global on/off and default pattern to it.

enum HapticFeedback {
    private static let enabledKey = "hapticsEnabled"
    private static let patternKey = "hapticPatternRawValue"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var pattern: Haptic {
        get {
            guard let raw = UserDefaults.standard.object(forKey: patternKey) as? Int,
                  let haptic = Haptic(rawValue: UInt8(raw))
            else { return .short }
            return haptic
        }
        set { UserDefaults.standard.set(Int(newValue.rawValue), forKey: patternKey) }
    }

    /// Fire the vibrate command if haptics are turned on; a no-op with no
    /// device connected. Called on physical presses (button, knob, tile
    /// touch), not on release or rotation, so it reads as a discrete tap
    /// confirmation rather than constant buzzing.
    static func trigger(on device: RazerStreamDevice?) {
        guard isEnabled, let device else { return }
        try? device.send(.vibrate(pattern))
    }
}
