import Foundation

// Device-wide preference (UserDefaults, not profile content) for dimming the
// panel after no input for a while; off by default so it never surprises an
// existing install. DeviceManager polls this and dims/wakes accordingly.
enum IdleDimming {
    private static let enabledKey = "idleDimmingEnabled"
    private static let minutesKey = "idleDimmingMinutes"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Minutes of no button/knob/touch input before the panel dims.
    static var minutes: Int {
        get { UserDefaults.standard.object(forKey: minutesKey) as? Int ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: minutesKey) }
    }
}
