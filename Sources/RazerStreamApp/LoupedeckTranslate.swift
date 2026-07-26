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

        var action: ControlAction? {
            switch self {
            case .mapped(let a):          return a
            case .approximate(let a, _):  return a
            case .unmapped:               return nil
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
                // A plugin action with saved parameters; the underlying action
                // is a plugin call, so there is nothing faithful to map to.
                let cmd = profileCommands[action] ?? p.payload.flatMap { profileCommands[$0] }
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
        private func translateMacro(_ macro: MacroCommand) -> Mapping {
            let steps = macro.actions ?? []
            guard !steps.isEmpty else {
                return .unmapped(reason: "Macro has no steps")
            }

            var actions: [ControlAction] = []
            var notes: [String] = []
            var failed: [String] = []

            for step in steps {
                let p = Self.parts(of: step)
                let mapping: Mapping
                if p.plugin == "@Generic" {
                    mapping = translateGeneric(verb: p.verb, payload: p.payload)
                } else {
                    mapping = .unmapped(reason: "Needs the \(p.plugin) plugin")
                }
                switch mapping {
                case .mapped(let a):
                    actions.append(a)
                case .approximate(let a, let note):
                    actions.append(a); notes.append(note)
                case .unmapped(let reason):
                    failed.append(reason)
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
            guard let payload, !payload.isEmpty else {
                return .unmapped(reason: "Action has no target")
            }

            switch verb {
            case "@ExecuteApplication":
                // Either a URL or an application path.
                if payload.hasPrefix("http://") || payload.hasPrefix("https://") {
                    return .mapped(.openURL(payload))
                }
                return .mapped(.launchApp(path: payload))

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
