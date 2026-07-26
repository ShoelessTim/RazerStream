import Foundation

// Turns Loupedeck action strings into RazerStream ControlActions.
//
// Action strings look like `$<plugin>___<action>___<payload>`, for example:
//
//   $@Generic___@ExecuteApplication___/Applications/Google Chrome.app
//   $@Generic___@ExecuteApplication___https://x.com
//   $@Generic___Loupedeck.GenericPlugin.PlaySoundDynamicAction___?filePath=~%2F...wav&volume=50
//   $@Generic___@Macro___<GUID>            (defined in the profile's macroCommands)
//   $@Generic___@ProfileAction___<GUID>    (defined in the profile's profileActions)
//   $DefaultMac___Volume
//   $Twitch___CreateClip                   (plugin; no equivalent here)
//
// The mapping is deliberately conservative. Anything that is not a faithful
// translation is reported rather than quietly turned into something that
// looks right but does the wrong thing on someone's deck; the import review
// step shows those so they can be reassigned by hand.

extension LoupedeckImport {

    /// What became of one Loupedeck action.
    enum Mapping {
        /// A faithful translation.
        case mapped(ControlAction)
        /// Translated, but the semantics are close rather than exact; the
        /// review step should draw attention to it.
        case approximate(ControlAction, note: String)
        /// No equivalent. The label is kept so the tile still reads correctly
        /// and can be reassigned.
        case unmapped(reason: String)
        /// Loupedeck's explicit "no action" (`@None`). Not a failure: the
        /// control was deliberately left blank, so the review step should
        /// pass over it rather than report it as needing attention.
        case empty

        var action: ControlAction? {
            switch self {
            case .mapped(let a):          return a
            case .approximate(let a, _):  return a
            case .unmapped, .empty:       return nil
            }
        }

        /// True when this control should be shown in the review step.
        var needsAttention: Bool {
            switch self {
            case .unmapped, .approximate: return true
            case .mapped, .empty:         return false
            }
        }
    }

    /// One translated control, ready to become a tile or knob.
    struct TranslatedControl {
        var label: String
        var mapping: Mapping
        /// Icon file inside the profile's ActionIcons directory, when present.
        var iconActionKey: String?
    }

    struct Translator {
        private let macros: [String: MacroCommand]
        private let profileCommands: [String: ProfileCommand]

        init(profile: Profile) {
            var m: [String: MacroCommand] = [:]
            for macro in profile.macroCommands ?? [] {
                if let name = macro.name { m[name] = macro }
            }
            macros = m

            var p: [String: ProfileCommand] = [:]
            for cmd in profile.profileActions ?? [] {
                // profileActions carry the full action string as `name`.
                if let name = cmd.name {
                    p[name] = cmd
                    if let guid = Self.payload(of: name) { p[guid] = cmd }
                }
            }
            profileCommands = p
        }

        /// Splits `$Plugin___Action___payload` into its parts. The payload can
        /// itself contain the separator in principle, so only the first two
        /// separators are treated as structural.
        private static func parts(of action: String) -> (plugin: String, verb: String, payload: String?) {
            let trimmed = action.hasPrefix("$") ? String(action.dropFirst()) : action
            let comps = trimmed.components(separatedBy: "___")
            let plugin = comps.first ?? ""
            let verb = comps.count > 1 ? comps[1] : ""
            let payload = comps.count > 2 ? comps[2...].joined(separator: "___") : nil
            return (plugin, verb, payload)
        }

        private static func payload(of action: String) -> String? { parts(of: action).payload }

        /// Human label for a control, preferring a macro's own display name.
        func label(for action: String) -> String {
            let p = Self.parts(of: action)
            if let guid = p.payload, let macro = macros[guid],
               let name = macro.displayName, !name.isEmpty {
                return name
            }
            if let cmd = profileCommands[action] ?? p.payload.flatMap({ profileCommands[$0] }),
               let name = cmd.displayName, !name.isEmpty {
                return name
            }
            // Fall back to the action verb, de-camel-cased: "CreateClip" reads
            // as "Create Clip" on a tile.
            let verb = p.verb.isEmpty ? p.plugin : p.verb
            return Self.humanize(verb)
        }

        func translate(_ action: String) -> TranslatedControl {
            let p = Self.parts(of: action)
            let text = label(for: action)

            switch (p.plugin, p.verb) {
            case ("@Generic", "@Macro"):
                guard let guid = p.payload, let macro = macros[guid] else {
                    return TranslatedControl(label: text,
                                             mapping: .unmapped(reason: "Macro definition not found in profile"),
                                             iconActionKey: action)
                }
                return TranslatedControl(label: text,
                                         mapping: translateMacro(macro),
                                         iconActionKey: action)

            case ("@Generic", "@ProfileAction"):
                // A saved, parameterised action. The common case by far is a
                // keyboard shortcut, which we can reproduce exactly; anything
                // else resolves to a plugin call with no equivalent.
                let cmd = profileCommands[action] ?? p.payload.flatMap { profileCommands[$0] }
                if let cmd, Self.parts(of: cmd.templateActionName ?? "").verb == "@KeyboardKey" {
                    return TranslatedControl(label: text,
                                             mapping: translateKeyboardKey(cmd),
                                             iconActionKey: action)
                }
                let origin = cmd?.templateActionName.map { Self.parts(of: $0).plugin } ?? "a plugin"
                return TranslatedControl(label: text,
                                         mapping: .unmapped(reason: "Needs the \(origin) plugin"),
                                         iconActionKey: action)

            case ("@Generic", _):
                return TranslatedControl(label: text,
                                         mapping: translateGeneric(verb: p.verb, payload: p.payload),
                                         iconActionKey: action)

            case ("DefaultMac", "Volume"):
                // Loupedeck models volume as one bidirectional adjustment; our
                // equivalent is the knob's Volume rotation preset, which the
                // caller applies as an up/down pair.
                return TranslatedControl(label: text, mapping: .mapped(.volumeUp), iconActionKey: action)

            case ("DefaultMac", "ResetVolume"):
                return TranslatedControl(
                    label: text,
                    mapping: .approximate(.volumeMute, note: "Loupedeck reset the volume; mapped to Mute"),
                    iconActionKey: action)

            default:
                return TranslatedControl(label: text,
                                         mapping: .unmapped(reason: "Needs the \(p.plugin) plugin"),
                                         iconActionKey: action)
            }
        }

        /// A macro is a list of steps. One step becomes a plain action; several
        /// become a sequence, which is what our multi-action macros are for.
        ///
        /// Steps can reference other macros, either spelled out as
        /// `$@Generic___@Macro___<GUID>` or as a bare GUID, so this recurses
        /// and flattens. `seen` guards against a macro that references itself
        /// directly or through a cycle, which would otherwise never terminate.
        private func translateMacro(_ macro: MacroCommand, seen: Set<String> = []) -> Mapping {
            let steps = macro.actions ?? []
            guard !steps.isEmpty else {
                return .unmapped(reason: "Macro has no steps")
            }

            var visited = seen
            if let name = macro.name { visited.insert(name) }

            var actions: [ControlAction] = []
            var notes: [String] = []
            var failed: [String] = []

            for step in steps {
                let p = Self.parts(of: step)
                let mapping: Mapping

                // A nested macro, either fully qualified or a bare GUID.
                let nestedKey: String? = {
                    if p.plugin == "@Generic", p.verb == "@Macro" { return p.payload }
                    if !step.contains("___"), macros[step] != nil { return step }
                    return nil
                }()

                if let key = nestedKey {
                    if visited.contains(key) {
                        mapping = .unmapped(reason: "Macro refers to itself")
                    } else if let nested = macros[key] {
                        mapping = translateMacro(nested, seen: visited)
                    } else {
                        mapping = .unmapped(reason: "Referenced macro not found in profile")
                    }
                } else if p.plugin == "@Generic" {
                    mapping = translateGeneric(verb: p.verb, payload: p.payload)
                } else {
                    mapping = .unmapped(reason: "Needs the \(p.plugin) plugin")
                }

                switch mapping {
                case .mapped(let a):
                    // Flatten a nested sequence rather than nesting one inside
                    // another; play time flattens anyway, and a flat list is
                    // what the macro editor shows.
                    if case .sequence(let inner) = a { actions.append(contentsOf: inner.map(\.action)) }
                    else { actions.append(a) }
                case .approximate(let a, let note):
                    if case .sequence(let inner) = a { actions.append(contentsOf: inner.map(\.action)) }
                    else { actions.append(a) }
                    notes.append(note)
                case .unmapped(let reason):
                    failed.append(reason)
                case .empty:
                    // An explicitly blank step; contributes nothing and is
                    // not a failure.
                    continue
                }
            }

            guard !actions.isEmpty else {
                return .unmapped(reason: failed.first ?? "No translatable steps")
            }
            let combined = actions.count == 1 ? actions[0] : .sequence(actions.map { MacroStep(action: $0) })
            if !failed.isEmpty {
                return .approximate(combined,
                                    note: "\(failed.count) of \(steps.count) steps could not be translated")
            }
            if let note = notes.first {
                return .approximate(combined, note: note)
            }
            return .mapped(combined)
        }

        /// The `@Generic` plugin is Loupedeck's own built-in set, and the only
        /// family with real equivalents here.
        private func translateGeneric(verb: String, payload: String?) -> Mapping {
            // Verbs that carry no payload by design, handled before the
            // has-a-target check below.
            switch verb {
            case "@None":
                return .empty
            case "@NextTouchPage":
                return .mapped(.nextPage)
            case "@PreviousTouchPage":
                return .mapped(.prevPage)
            case "@ButtonClock":
                return .unmapped(reason: "Shows a clock; set the tile's Content to Clock instead")
            default:
                break
            }

            guard let payload, !payload.isEmpty else {
                return .unmapped(reason: "Action has no target")
            }

            switch verb {
            case "@ChangeTouchPage":
                // "Main|<workspace>|<page>". The target page lives inside a
                // Loupedeck workspace and its id does not correspond to any
                // page we create on import, so there is no index to point at.
                return .unmapped(reason: "Jumps to a specific page; choose the page by hand")

            case let v where v.hasSuffix("DateTimeDynamicAction"):
                return .unmapped(reason: "Shows the date or time; set the tile's Content to Clock instead")

            case "@ExecuteApplication":
                // Either a URL or an application path.
                if payload.hasPrefix("http://") || payload.hasPrefix("https://") {
                    return .mapped(.openURL(payload))
                }
                return .mapped(.launchApp(path: payload))

            case "@MouseClick":
                // Payload is a modifier held during the click ("AltLeft",
                // "ControlLeft"); we can click but cannot hold the modifier,
                // so this is close rather than exact.
                return .approximate(.mouseClick,
                                    note: "Loupedeck held \(Self.humanize(payload)) during the click; the modifier is not carried over")

            case "@MouseClickRight":
                return .unmapped(reason: "Right click has no equivalent action yet")

            case "@ChangeWorkspace":
                // "Main|<workspace GUID>". Loupedeck workspaces are a grouping
                // above pages with no equivalent here, and the target is a
                // GUID rather than a page index, so there is nothing faithful
                // to point this at.
                return .unmapped(reason: "Switches a Loupedeck workspace; pick a page for this by hand")

            case let v where v.hasSuffix("PlaySoundDynamicAction"):
                // ?filePath=<percent encoded>&volume=50
                guard let path = Self.queryValue("filePath", in: payload) else {
                    return .unmapped(reason: "Sound action has no file path")
                }
                let expanded = (path as NSString).expandingTildeInPath
                let quoted = expanded.replacingOccurrences(of: "'", with: "'\\''")
                return .approximate(.shellCommand("afplay '\(quoted)'"),
                                    note: "Plays through afplay; Loupedeck's per sound volume is not carried over")

            default:
                return .unmapped(reason: "Unsupported built-in action")
            }
        }

        /// A saved keyboard shortcut. The stored value has four fields
        /// separated by `___`, of which the third is the Mac rendering:
        ///
        ///   ControlOrCommand+Control+Space___4108___Cmd+Ctrl+Space___mac-49#...
        ///
        /// so we take that field and rewrite its tokens into the form the
        /// keystroke engine parses. Anything with a key we cannot press is
        /// reported rather than silently sent as a different shortcut.
        private func translateKeyboardKey(_ cmd: ProfileCommand) -> Mapping {
            guard let raw = cmd.actionParameters?.parameters?["keyboardKey"] else {
                return .unmapped(reason: "Shortcut has no key recorded")
            }
            let fields = raw.components(separatedBy: "___")
            // Prefer the Mac field; fall back to the portable first field.
            let combo = fields.count >= 3 ? fields[2] : (fields.first ?? "")
            guard !combo.isEmpty else {
                return .unmapped(reason: "Shortcut has no key recorded")
            }

            var tokens: [String] = []
            for token in combo.components(separatedBy: "+") {
                guard let mapped = Self.keyToken(token) else {
                    return .unmapped(reason: "Uses the \(token) key, which cannot be sent yet")
                }
                tokens.append(mapped)
            }
            return .mapped(.keystroke(tokens.joined(separator: "+")))
        }

        /// Loupedeck key names to the names the keystroke engine understands.
        /// Returns nil for keys with no virtual key code available, so the
        /// caller can report them instead of substituting something wrong.
        private static func keyToken(_ token: String) -> String? {
            switch token.lowercased() {
            case "cmd", "command":              return "cmd"
            case "ctrl", "control":             return "ctrl"
            case "shift":                       return "shift"
            case "opt", "option", "alt":        return "opt"
            case "fn":                          return "fn"
            case "arrowleft":                   return "left"
            case "arrowright":                  return "right"
            case "arrowup":                     return "up"
            case "arrowdown":                   return "down"
            case "space", "spacebar":           return "space"
            case "enter", "return":             return "return"
            case "esc", "escape":               return "escape"
            case "tab":                         return "tab"
            case "backspace", "delete":         return "delete"
            case "comma":                       return ","
            case "period", "dot":               return "."
            case "slash":                       return "/"
            case "backslash":                   return "\\"
            case "semicolon":                   return ";"
            case "quote", "apostrophe":         return "'"
            case "minus", "oemminus":           return "-"
            case "plus", "equal", "oemplus":    return "="
            case "backquote", "grave", "oem3":  return "`"
            // Windows style OEM names still appear in saved Mac shortcuts.
            case "oem1":                        return ";"
            case "oem2":                        return "/"
            case "oem4":                        return "["
            case "oem5":                        return "\\"
            case "oem6":                        return "]"
            case "oem7":                        return "'"
            default:
                let t = token.lowercased()
                // Single letters and digits pass through; so do f1 to f12.
                if t.count == 1, t.first!.isLetter || t.first!.isNumber { return t }
                if t.first == "f", Int(t.dropFirst()).map({ (1...12).contains($0) }) == true { return t }
                return nil
            }
        }

        /// Reads one value out of a `?a=b&c=d` style payload, percent decoded.
        private static func queryValue(_ key: String, in payload: String) -> String? {
            let body = payload.hasPrefix("?") ? String(payload.dropFirst()) : payload
            for pair in body.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                guard kv.count == 2, kv[0] == key else { continue }
                return kv[1].removingPercentEncoding ?? kv[1]
            }
            return nil
        }

        /// "CreateClip" to "Create Clip"; used only for fallback labels.
        private static func humanize(_ s: String) -> String {
            guard !s.isEmpty else { return "" }
            var out = ""
            for (i, ch) in s.enumerated() {
                if i > 0, ch.isUppercase { out.append(" ") }
                out.append(ch)
            }
            return out
        }
    }
}
