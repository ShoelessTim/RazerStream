import SwiftUI
import AppKit

// A "press the keys" shortcut recorder, like System Settings uses.
// Produces combo strings in ActionEngine format ("cmd+shift+k").

struct KeystrokeRecorder: View {
    @Binding var combo: String
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                HStack {
                    Image(systemName: recording ? "record.circle.fill" : "keyboard")
                        .foregroundStyle(recording ? .red : .secondary)
                    Text(recording
                         ? "Press keys…"
                         : (combo.isEmpty ? "Click to record shortcut" : Self.pretty(combo)))
                        .font(combo.isEmpty || recording ? .callout : .system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recording ? .red : Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if !combo.isEmpty && !recording {
                Button {
                    combo = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onDisappear { stopRecording() }
    }

    // MARK: - Recording

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(event)
            return nil   // swallow the event while recording
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func capture(_ event: NSEvent) {
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.shift)   { parts.append("shift") }
        if flags.contains(.option)  { parts.append("alt") }
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.function), Self.keyName(for: event.keyCode) == nil {
            parts.append("fn")
        }

        guard let key = Self.keyName(for: event.keyCode)
                ?? event.charactersIgnoringModifiers?.lowercased(),
              !key.isEmpty else { return }
        parts.append(key)

        combo = parts.joined(separator: "+")
        stopRecording()
    }

    // MARK: - Display helpers

    /// "cmd+shift+k" → "⌘⇧K"
    static func pretty(_ combo: String) -> String {
        combo.split(separator: "+").map { part -> String in
            switch part {
            case "cmd":   return "⌘"
            case "shift": return "⇧"
            case "alt":   return "⌥"
            case "ctrl":  return "⌃"
            case "fn":    return "fn "
            case "left":  return "←"
            case "right": return "→"
            case "up":    return "↑"
            case "down":  return "↓"
            case "space": return "Space"
            case "return", "enter": return "↩"
            case "escape", "esc":   return "⎋"
            case "delete", "backspace": return "⌫"
            case "tab":   return "⇥"
            default:      return part.uppercased()
            }
        }.joined()
    }

    /// Reverse of ActionEngine.keyCodes (canonical names only).
    static func keyName(for keyCode: UInt16) -> String? {
        Self.reverseKeyCodes[keyCode]
    }

    private static let reverseKeyCodes: [UInt16: String] = {
        var map: [UInt16: String] = [:]
        // Insertion order matters: canonical names overwrite aliases
        for (name, code) in ActionEngine.keyCodes {
            map[code] = name
        }
        // Force canonical names for keys with aliases
        map[0x24] = "return"
        map[0x33] = "delete"
        map[0x35] = "escape"
        return map
    }()
}
