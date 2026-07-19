import Foundation
import AppKit
import Carbon.HIToolbox

// Executes ControlActions on the Mac. Page-navigation actions are routed back
// to the caller via `pageHandler` since they mutate app state, not system state.

enum ActionEngine {

    enum PageNav { case goto(Int), next, prev }

    // Device brightness lives on the profile, not the system, so it routes
    // back through the same closure pattern as page navigation rather than
    // being handled inline here.
    enum DeviceAdjustment {
        case brightnessUp, brightnessDown
        case ledBrightnessUp, ledBrightnessDown
        case bothBrightnessUp, bothBrightnessDown
    }

    static func perform(
        _ action: ControlAction,
        amount: Int = 1,
        pageHandler: @escaping (PageNav) -> Void = { _ in },
        deviceHandler: @escaping (DeviceAdjustment, Int) -> Void = { _, _ in }
    ) {
        switch action {
        case .sequence(let steps):
            // Scheduled on the main queue so AppKit work and the DeviceManager
            // handlers stay on the same thread they already use. Delays use
            // asyncAfter rather than Task/await to avoid Swift 6 sending
            // diagnostics on non-Sendable handler closures from @MainActor.
            runSequence(
                steps,
                amount: amount,
                pageHandler: pageHandler,
                deviceHandler: deviceHandler
            )

        default:
            performImmediate(
                action,
                amount: amount,
                pageHandler: pageHandler,
                deviceHandler: deviceHandler
            )
        }
    }

    /// Holds page/device handlers across delayed main-queue hops. Always
    /// invoked on the main queue (same as DeviceManager), so @unchecked
    /// Sendable is the honest escape hatch Swift 6 needs for non-Sendable
    /// escaping closures scheduled with DispatchQueue.main.asyncAfter.
    private final class MacroContext: @unchecked Sendable {
        let amount: Int
        let pageHandler: (PageNav) -> Void
        let deviceHandler: (DeviceAdjustment, Int) -> Void
        let steps: [MacroStep]

        init(
            steps: [MacroStep],
            amount: Int,
            pageHandler: @escaping (PageNav) -> Void,
            deviceHandler: @escaping (DeviceAdjustment, Int) -> Void
        ) {
            self.steps = steps
            self.amount = amount
            self.pageHandler = pageHandler
            self.deviceHandler = deviceHandler
        }
    }

    /// Runs macro steps in order with their delays. Nested `.sequence` steps
    /// are flattened so a malformed profile cannot recurse forever. Failures
    /// in individual steps are logged by the leaf handlers and the rest of
    /// the macro continues (v1 policy: keep going).
    private static func runSequence(
        _ steps: [MacroStep],
        amount: Int,
        pageHandler: @escaping (PageNav) -> Void,
        deviceHandler: @escaping (DeviceAdjustment, Int) -> Void
    ) {
        let flat = flattenSteps(steps)
        guard !flat.isEmpty else { return }
        let context = MacroContext(
            steps: flat,
            amount: amount,
            pageHandler: pageHandler,
            deviceHandler: deviceHandler
        )
        scheduleStep(index: 0, context: context)
    }

    private static func scheduleStep(index: Int, context: MacroContext) {
        let work = {
            guard index < context.steps.count else { return }
            let step = context.steps[index]
            performImmediate(
                step.action,
                amount: context.amount,
                pageHandler: context.pageHandler,
                deviceHandler: context.deviceHandler
            )
            let next = index + 1
            guard next < context.steps.count else { return }
            let delay = TimeInterval(step.delayAfterMs) / 1000.0
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    scheduleStep(index: next, context: context)
                }
            } else {
                // Bounce to the next runloop turn so a long chain of
                // zero-delay steps cannot starve input handling.
                DispatchQueue.main.async {
                    scheduleStep(index: next, context: context)
                }
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Expands nested sequences into a single ordered list of leaf steps.
    private static func flattenSteps(_ steps: [MacroStep]) -> [MacroStep] {
        var out: [MacroStep] = []
        for step in steps {
            if case .sequence(let nested) = step.action {
                out.append(contentsOf: flattenSteps(nested))
            } else if case .none = step.action {
                // Skip empty steps so a half-edited macro doesn't pause on blanks.
                continue
            } else {
                out.append(step)
            }
        }
        return out
    }

    /// Single non-sequence action. Callers that need macros use `perform`.
    private static func performImmediate(
        _ action: ControlAction,
        amount: Int,
        pageHandler: (PageNav) -> Void,
        deviceHandler: (DeviceAdjustment, Int) -> Void
    ) {
        switch action {
        case .none, .sequence:
            // .sequence should never reach here; flatten/perform routes it.
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
            if hasAccessibility { for _ in 0..<amount { sendMediaKey(0) } }   // NX_KEYTYPE_SOUND_UP
            else { runAppleScript("set volume output volume ((output volume of (get volume settings)) + \(6 * amount))") }
        case .volumeDown:
            if hasAccessibility { for _ in 0..<amount { sendMediaKey(1) } }   // NX_KEYTYPE_SOUND_DOWN
            else { runAppleScript("set volume output volume ((output volume of (get volume settings)) - \(6 * amount))") }
        case .volumeMute:
            if hasAccessibility { sendMediaKey(7) }   // NX_KEYTYPE_MUTE
            else { runAppleScript("set volume output muted (not (output muted of (get volume settings)))") }

        case .mouseScrollUp:
            sendScroll(vertical: Int32(amount), horizontal: 0)
        case .mouseScrollDown:
            sendScroll(vertical: -Int32(amount), horizontal: 0)
        case .mouseScrollLeft:
            sendScroll(vertical: 0, horizontal: -Int32(amount))
        case .mouseScrollRight:
            sendScroll(vertical: 0, horizontal: Int32(amount))
        case .mouseClick:
            sendMouseClick()

        case .gotoPage(let p): pageHandler(.goto(p))
        case .nextPage:        pageHandler(.next)
        case .prevPage:        pageHandler(.prev)

        case .brightnessUp:   deviceHandler(.brightnessUp, amount)
        case .brightnessDown: deviceHandler(.brightnessDown, amount)
        case .ledBrightnessUp:   deviceHandler(.ledBrightnessUp, amount)
        case .ledBrightnessDown: deviceHandler(.ledBrightnessDown, amount)
        case .bothBrightnessUp:   deviceHandler(.bothBrightnessUp, amount)
        case .bothBrightnessDown: deviceHandler(.bothBrightnessDown, amount)

        case .showApp:
            // Reopens the window if it was closed, or fronts it if open;
            // goes through the SwiftUI openWindow bridge (see AppActions)
            DispatchQueue.main.async {
                AppActions.shared.showMainWindow?()
            }
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

    /// Posts a scroll-wheel event. Positive `vertical` scrolls up (content
    /// moves down); positive `horizontal` scrolls right. Line units so each
    /// knob detent is one discrete step; `amount` multiplies for fast turns.
    /// Requires Accessibility, same as keystrokes.
    private static func sendScroll(vertical: Int32, horizontal: Int32) {
        guard hasAccessibility else {
            NSLog("Scroll skipped: Accessibility permission not granted")
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        // wheelCount 2 so both axes are valid; unused axis is 0.
        guard let event = CGEvent(
            scrollWheelEvent2Source: src,
            units: .line,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ) else {
            NSLog("Scroll: failed to create CGEvent")
            return
        }
        event.post(tap: .cghidEventTap)
    }

    /// Left-clicks at the current cursor position. Useful as a knob press
    /// alongside scroll rotation. Requires Accessibility.
    private static func sendMouseClick() {
        guard hasAccessibility else {
            NSLog("Mouse click skipped: Accessibility permission not granted")
            return
        }
        let loc = NSEvent.mouseLocation
        // AppKit y is bottom-up; CGEvent is top-down.
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) })
                ?? NSScreen.main else { return }
        let cgPoint = CGPoint(x: loc.x, y: screen.frame.maxY - loc.y)
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                           mouseCursorPosition: cgPoint, mouseButton: .left)
        let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                         mouseCursorPosition: cgPoint, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
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
