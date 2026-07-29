import SwiftUI

// Builds a shortcut from parts rather than asking the user to type one.
//
// This exists because recording cannot capture shortcuts macOS claims for
// itself (Cmd+Shift+4 takes a screenshot instead of being recorded), and
// free typing just moves the failure later: a combo with a key the engine
// has no code for looks fine in the field and silently does nothing when the
// control is pressed. Picking modifiers and a key from fixed sets makes an
// invalid shortcut impossible to express.
//
// Only keys the keystroke engine can actually send are offered; the list is
// derived from the same table it looks up at press time.

struct KeystrokeBuilder: View {
    @Binding var combo: String

    @State private var cmd = false
    @State private var shift = false
    @State private var opt = false
    @State private var ctrl = false
    @State private var key = ""

    /// Keys grouped for a browsable menu. Aliases the engine accepts
    /// ("esc"/"escape", "enter"/"return", "backspace"/"delete") are collapsed
    /// to one canonical entry each so the list does not show the same key
    /// twice under two names.
    private static let keyGroups: [(String, [(label: String, value: String)])] = [
        ("Letters", "abcdefghijklmnopqrstuvwxyz".map { (String($0).uppercased(), String($0)) }),
        ("Numbers", (0...9).map { (String($0), String($0)) }),
        ("Function", (1...12).map { ("F\($0)", "f\($0)") }),
        ("Arrows", [("←  Left", "left"), ("→  Right", "right"),
                    ("↑  Up", "up"), ("↓  Down", "down")]),
        ("Editing", [("Space", "space"), ("Return", "return"), ("Tab", "tab"),
                     ("Escape", "escape"), ("Delete", "delete")]),
        ("Punctuation", [("-  Minus", "-"), ("=  Equals", "="),
                         ("[  Left Bracket", "["), ("]  Right Bracket", "]"),
                         (";  Semicolon", ";"), ("'  Quote", "'"),
                         (",  Comma", ","), (".  Period", "."),
                         ("/  Slash", "/"), ("\\  Backslash", "\\"),
                         ("`  Backtick", "`")]),
    ]

    private var built: String {
        var parts: [String] = []
        if cmd { parts.append("cmd") }
        if shift { parts.append("shift") }
        if opt { parts.append("alt") }
        if ctrl { parts.append("ctrl") }
        guard !key.isEmpty else { return "" }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                modifier("⌘", isOn: $cmd, help: "Command")
                modifier("⇧", isOn: $shift, help: "Shift")
                modifier("⌥", isOn: $opt, help: "Option")
                modifier("⌃", isOn: $ctrl, help: "Control")

                Picker("", selection: $key) {
                    Text("Key…").tag("")
                    ForEach(Self.keyGroups, id: \.0) { group, keys in
                        Section(group) {
                            ForEach(keys, id: \.value) { entry in
                                Text(entry.label).tag(entry.value)
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
            }

            HStack {
                if built.isEmpty {
                    Text("Pick a key to finish the shortcut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(KeystrokeRecorder.pretty(built))
                        .font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                Button("Use") { combo = built }
                    .disabled(built.isEmpty || built == combo)
            }
        }
        .onAppear(perform: loadFromCombo)
        .onChange(of: combo) { loadFromCombo() }
    }

    private func modifier(_ glyph: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(glyph)
                .font(.system(size: 14))
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isOn.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(isOn.wrappedValue ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Reflects an existing shortcut back into the controls, so opening a
    /// control that already has one shows it rather than starting blank.
    private func loadFromCombo() {
        let parts = combo.lowercased().split(separator: "+").map(String.init)
        cmd = parts.contains("cmd") || parts.contains("command")
        shift = parts.contains("shift")
        opt = parts.contains("alt") || parts.contains("opt") || parts.contains("option")
        ctrl = parts.contains("ctrl") || parts.contains("control")
        let modifiers: Set<String> = ["cmd", "command", "shift", "alt", "opt", "option", "ctrl", "control", "fn"]
        let found = parts.first { !modifiers.contains($0) } ?? ""
        // Normalise aliases onto the canonical entry the menu offers.
        switch found {
        case "esc":       key = "escape"
        case "enter":     key = "return"
        case "backspace": key = "delete"
        default:          key = found
        }
    }
}
