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
// action for clockwise and another for counterclockwise, each of these is a
// single choice whose direction is derived from
// KnobDirection.clockwiseIncreases. "Custom" is the escape hatch for
// anything else, or any pairing not covered by a preset here.
enum KnobRotationMode: Equatable, CaseIterable {
    case none
    case volume
    case brightness
    case ledBrightness
    case combinedBrightness
    case pageNavigation
    case mediaTrack
    case mouseScrollVertical
    case mouseScrollHorizontal
    case custom

    var displayName: String {
        switch self {
        case .none:          return "None"
        case .volume:        return "Volume"
        case .brightness:    return "Screen Brightness"
        case .ledBrightness: return "Button LED Brightness"
        case .combinedBrightness: return "Screen + LED Brightness"
        case .pageNavigation: return "Page Navigation"
        case .mediaTrack:    return "Next / Previous Track"
        case .mouseScrollVertical:   return "Mouse Scroll (Vertical)"
        case .mouseScrollHorizontal: return "Mouse Scroll (Horizontal)"
        case .custom:        return "Custom…"
        }
    }

    /// What "clockwise" means for this preset, for the direction caption;
    /// .none/.custom have no fixed meaning so callers shouldn't ask.
    var increaseVerb: (clockwise: String, counterClockwise: String)? {
        switch self {
        case .volume:         return ("raises the volume", "lowers it")
        case .brightness:     return ("brightens the screen", "dims it")
        case .ledBrightness:  return ("brightens the button LEDs", "dims them")
        case .combinedBrightness: return ("brightens the screen and LEDs together", "dims them together")
        case .pageNavigation: return ("goes to the next page", "goes back")
        case .mediaTrack:     return ("skips to the next track", "goes to the previous one")
        // Scroll: "increases" = further down the page / further right, matching
        // a typical mouse wheel (roll away / turn right = scroll content down).
        case .mouseScrollVertical:   return ("scrolls down", "scrolls up")
        case .mouseScrollHorizontal: return ("scrolls right", "scrolls left")
        case .none, .custom:  return nil
        }
    }

    static func detect(clockwise: ControlAction, counterClockwise: ControlAction) -> KnobRotationMode {
        if clockwise == .none && counterClockwise == .none { return .none }
        if isPair(clockwise, counterClockwise, .volumeUp, .volumeDown) { return .volume }
        if isPair(clockwise, counterClockwise, .brightnessUp, .brightnessDown) { return .brightness }
        if isPair(clockwise, counterClockwise, .ledBrightnessUp, .ledBrightnessDown) { return .ledBrightness }
        if isPair(clockwise, counterClockwise, .bothBrightnessUp, .bothBrightnessDown) { return .combinedBrightness }
        if isPair(clockwise, counterClockwise, .nextPage, .prevPage) { return .pageNavigation }
        if isPair(clockwise, counterClockwise, .mediaNext, .mediaPrevious) { return .mediaTrack }
        if isPair(clockwise, counterClockwise, .mouseScrollDown, .mouseScrollUp) { return .mouseScrollVertical }
        if isPair(clockwise, counterClockwise, .mouseScrollRight, .mouseScrollLeft) { return .mouseScrollHorizontal }
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
        case .ledBrightness:
            return clockwiseIncreases ? (.ledBrightnessUp, .ledBrightnessDown) : (.ledBrightnessDown, .ledBrightnessUp)
        case .combinedBrightness:
            return clockwiseIncreases ? (.bothBrightnessUp, .bothBrightnessDown) : (.bothBrightnessDown, .bothBrightnessUp)
        case .pageNavigation:
            return clockwiseIncreases ? (.nextPage, .prevPage) : (.prevPage, .nextPage)
        case .mediaTrack:
            return clockwiseIncreases ? (.mediaNext, .mediaPrevious) : (.mediaPrevious, .mediaNext)
        case .mouseScrollVertical:
            // "Increases" = scroll down (further into the document).
            return clockwiseIncreases
                ? (.mouseScrollDown, .mouseScrollUp)
                : (.mouseScrollUp, .mouseScrollDown)
        case .mouseScrollHorizontal:
            return clockwiseIncreases
                ? (.mouseScrollRight, .mouseScrollLeft)
                : (.mouseScrollLeft, .mouseScrollRight)
        case .custom:
            return (.none, .none)   // caller should leave existing fields alone in this case
        }
    }

    private static func isPair(_ a: ControlAction, _ b: ControlAction, _ up: ControlAction, _ down: ControlAction) -> Bool {
        (a == up && b == down) || (a == down && b == up)
    }
}
