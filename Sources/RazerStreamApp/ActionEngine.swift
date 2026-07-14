import Foundation
import AppKit
import Carbon.HIToolbox

// Executes ControlActions on the Mac. Page-navigation actions are routed back
// to the caller via `pageHandler` since they mutate app state, not system state.

enum ActionEngine {

    enum PageNav { case goto(Int), next, prev }

    static func perform(_ action: ControlAction, pageHandler: (PageNav) -> Void = { _ in }) {
        switch action {
        case .none:
            break

        case .launchApp(let path):
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error { NSLog("launchApp failed: \(error)") }
            }

        case .openURL(let urlString):
            // Default to https when the scheme is missing
            let full = urlString.contains("://") ? urlString : "https://\(urlString)"
            if let url = URL(string: full) {
                NSWorkspace.shared.open(url)
            } else {
                NSLog("openURL: invalid URL \(urlString)")
            }

        case .shellCommand(let cmd):
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", cmd]
            try? task.run()

        case .appleScript(let source):
            runAppleScript(source)

        case .keystroke(let combo):
            sendKeystroke(combo)

        case .mediaPlayPause: sendMediaKey(16)   // NX_KEYTYPE_PLAY
        case .mediaNext:      sendMediaKey(19)   // NX_KEYTYPE_FAST
        case .mediaPrevious:  sendMediaKey(20)   // NX_KEYTYPE_REWIND

        // Hardware key events show the native on-screen volume HUD; they need
        // the Accessibility grant, so fall back to silent AppleScript without it
        case .volumeUp:
            if hasAccessibility { sendMediaKey(0) }   // NX_KEYTYPE_SOUND_UP
            else { runAppleScript("set volume output volume ((output volume of (get volume settings)) + 6)") }
        case .volumeDown:
            if hasAccessibility { sendMediaKey(1) }   // NX_KEYTYPE_SOUND_DOWN
            else { runAppleScript("set volume output volume ((output volume of (get volume settings)) - 6)") }
        case .volumeMute:
            if hasAccessibility { sendMediaKey(7) }   // NX_KEYTYPE_MUTE
            else { runAppleScript("set volume output muted (not (output muted of (get volume settings)))") }

        case .gotoPage(let p): pageHandler(.goto(p))
        case .nextPage:        pageHandler(.next)
        case .prevPage:        pageHandler(.prev)
        }
    }

    private static func runAppleScript(_ source: String) {
        // NSAppleScript is main-thread only; running it elsewhere fails silently
        DispatchQueue.main.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { NSLog("AppleScript error: \(error)") }
        }
    }

    // MARK: - Keystrokes

    /// True when macOS lets us post keyboard and media events.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show the grant prompt once; safe to call repeatedly.
    static func requestAccessibility() {
        // Literal key; kAXTrustedCheckOptionPrompt is a global var that Swift 6
        // strict concurrency rejects
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Sends a key combo like "cmd+shift+k", "f5", "ctrl+left", "space".
    /// Requires the Accessibility permission; check hasAccessibility first.
    static func sendKeystroke(_ combo: String) {
        guard hasAccessibility else {
            NSLog("Keystroke skipped: Accessibility permission not granted")
            return
        }

        var flags: CGEventFlags = []
        var keyName = ""

        for part in combo.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command":   flags.insert(.maskCommand)
            case "shift":            flags.insert(.maskShift)
            case "alt", "opt", "option": flags.insert(.maskAlternate)
            case "ctrl", "control":  flags.insert(.maskControl)
            case "fn":               flags.insert(.maskSecondaryFn)
            default:                 keyName = part
            }
        }

        guard let keyCode = Self.keyCodes[keyName] else {
            NSLog("Unknown key: \(keyName) in combo \(combo)")
            return
        }

        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Posts a hardware media key (play/pause, next, previous) system event.
    private static func sendMediaKey(_ key: Int32) {
        func post(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            if let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1
            ) {
                event.cgEvent?.post(tap: .cghidEventTap)
            }
        }
        post(down: true)
        post(down: false)
    }

    // US-layout virtual key codes (Carbon kVK_*)
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
        "9": 0x19, "7": 0x1A, "8": 0x1C, "0": 0x1D,
        "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26,
        "k": 0x28, "n": 0x2D, "m": 0x2E,
        "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31,
        "delete": 0x33, "backspace": 0x33, "escape": 0x35, "esc": 0x35,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60,
        "f6": 0x61, "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D,
        "f11": 0x67, "f12": 0x6F,
        "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E, ";": 0x29, "'": 0x27,
        ",": 0x2B, ".": 0x2F, "/": 0x2C, "\\": 0x2A, "`": 0x32,
    ]
}
