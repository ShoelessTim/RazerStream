import Foundation
import AppKit

// Executes ControlActions on the Mac.

enum ActionEngine {

    static func perform(_ action: ControlAction) {
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

        case .shellCommand(let cmd):
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", cmd]
            try? task.run()

        case .appleScript(let source):
            DispatchQueue.global().async {
                if let script = NSAppleScript(source: source) {
                    var error: NSDictionary?
                    script.executeAndReturnError(&error)
                    if let error { NSLog("AppleScript error: \(error)") }
                }
            }

        case .volumeUp:
            runAppleScript("set volume output volume ((output volume of (get volume settings)) + 6)")
        case .volumeDown:
            runAppleScript("set volume output volume ((output volume of (get volume settings)) - 6)")
        case .volumeMute:
            runAppleScript("set volume output muted (not (output muted of (get volume settings)))")
        }
    }

    private static func runAppleScript(_ source: String) {
        DispatchQueue.global().async {
            NSAppleScript(source: source)?.executeAndReturnError(nil)
        }
    }
}
