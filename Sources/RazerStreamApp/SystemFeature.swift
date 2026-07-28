import Foundation

// Named macOS features, offered as their own group in the action picker.
//
// Every one of these could be built by hand from a keystroke or a shell
// command, but two things make a curated list worth having. Most people do
// not know that Screenshot Selection is Cmd+Shift+4. And the shortcut
// recorder physically cannot capture these: macOS intercepts its own
// shortcuts at the window server, so pressing Cmd+Shift+4 while recording
// takes a screenshot instead of recording the combo. Picking from a list
// sidesteps that entirely.
//
// Each case carries how it should actually be performed. Keystrokes are
// preferred where a real system shortcut exists, because that runs the user's
// own configured behaviour (their screenshot save location, format, and so
// on) rather than a parallel implementation that ignores their settings.

enum SystemFeature: String, Codable, Equatable, CaseIterable {
    // Screenshots and recording
    case screenshotSelection
    case screenshotFullScreen
    case screenshotWindow
    case screenshotToClipboard
    case screenshotUI

    // Windows and navigation
    case missionControl
    case appWindows
    case spotlight
    case launchpad

    // Mac display and keyboard (distinct from the deck's own brightness)
    case macBrightnessUp
    case macBrightnessDown
    case keyboardBacklightUp
    case keyboardBacklightDown

    // Session
    case lockScreen
    case screenSaver
    case sleepDisplay
    case forceQuitDialog
    case emptyTrash
    case toggleDarkMode

    var displayName: String {
        switch self {
        case .screenshotSelection:  return "Screenshot: Selection"
        case .screenshotFullScreen: return "Screenshot: Entire Screen"
        case .screenshotWindow:     return "Screenshot: Window"
        case .screenshotToClipboard: return "Screenshot: Selection to Clipboard"
        case .screenshotUI:         return "Screenshot & Recording Tools"
        case .missionControl:       return "Mission Control"
        case .appWindows:           return "App Windows (Exposé)"
        case .spotlight:            return "Spotlight Search"
        case .launchpad:            return "Launchpad"
        case .macBrightnessUp:      return "Mac Display Brightness +"
        case .macBrightnessDown:    return "Mac Display Brightness −"
        case .keyboardBacklightUp:  return "Keyboard Backlight +"
        case .keyboardBacklightDown: return "Keyboard Backlight −"
        case .lockScreen:           return "Lock Screen"
        case .screenSaver:          return "Start Screen Saver"
        case .sleepDisplay:         return "Sleep Display"
        case .forceQuitDialog:      return "Force Quit Window"
        case .emptyTrash:           return "Empty Trash"
        case .toggleDarkMode:       return "Toggle Dark Mode"
        }
    }

    /// Grouping for the picker, so twenty entries stay browsable.
    var group: String {
        switch self {
        case .screenshotSelection, .screenshotFullScreen, .screenshotWindow,
             .screenshotToClipboard, .screenshotUI:
            return "Screenshots"
        case .missionControl, .appWindows, .spotlight, .launchpad:
            return "Windows & Search"
        case .macBrightnessUp, .macBrightnessDown,
             .keyboardBacklightUp, .keyboardBacklightDown:
            return "Display & Keyboard"
        case .lockScreen, .screenSaver, .sleepDisplay,
             .forceQuitDialog, .emptyTrash, .toggleDarkMode:
            return "Session"
        }
    }

    static var groups: [String] {
        var seen: [String] = []
        for f in allCases where !seen.contains(f.group) { seen.append(f.group) }
        return seen
    }

    /// Anything the user should know before relying on it.
    var caveat: String? {
        switch self {
        case .macBrightnessUp, .macBrightnessDown:
            return "Adjusts the Mac's own display, not the deck's screen. Not every Mac accepts this."
        case .keyboardBacklightUp, .keyboardBacklightDown:
            return "Only does something on a Mac with a backlit keyboard."
        case .launchpad:
            return "Needs a Launchpad shortcut assigned in System Settings > Keyboard Shortcuts."
        case .screenshotWindow:
            return "Opens selection mode, then switches to window capture; click the window you want."
        default:
            return nil
        }
    }

    /// How to carry it out. Keystrokes run the user's own system behaviour and
    /// settings, so they are preferred wherever a real shortcut exists.
    enum Mechanism {
        case keystroke(String)
        /// A keystroke, then a second key after a short pause; window capture
        /// needs Space pressed once selection mode is up.
        case keystrokeThen(String, String)
        case mediaKey(Int32)
        case shell(String)
        case appleScript(String)
    }

    var mechanism: Mechanism {
        switch self {
        case .screenshotSelection:   return .keystroke("cmd+shift+4")
        case .screenshotFullScreen:  return .keystroke("cmd+shift+3")
        case .screenshotWindow:      return .keystrokeThen("cmd+shift+4", "space")
        case .screenshotToClipboard: return .keystroke("cmd+ctrl+shift+4")
        case .screenshotUI:          return .keystroke("cmd+shift+5")

        case .missionControl:        return .keystroke("ctrl+up")
        case .appWindows:            return .keystroke("ctrl+down")
        case .spotlight:             return .keystroke("cmd+space")
        case .launchpad:             return .keystroke("f4")

        // NX_KEYTYPE_BRIGHTNESS_UP / DOWN and ILLUMINATION_UP / DOWN
        case .macBrightnessUp:       return .mediaKey(2)
        case .macBrightnessDown:     return .mediaKey(3)
        case .keyboardBacklightUp:   return .mediaKey(21)
        case .keyboardBacklightDown: return .mediaKey(22)

        case .lockScreen:            return .keystroke("cmd+ctrl+q")
        case .forceQuitDialog:       return .keystroke("cmd+alt+escape")
        case .screenSaver:
            return .shell("open -a ScreenSaverEngine")
        case .sleepDisplay:
            return .shell("pmset displaysleepnow")
        case .emptyTrash:
            return .appleScript("tell application \"Finder\" to empty trash")
        case .toggleDarkMode:
            return .appleScript(
                "tell application \"System Events\" to tell appearance preferences "
                + "to set dark mode to not dark mode")
        }
    }
}
