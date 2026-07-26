import Foundation
import AppKit

// Reads profiles written by the retired Loupedeck software (now the Logi
// Plugin Service) so a user coming from that app keeps their layout.
//
// Everything here was derived from real profile data on disk, not guesswork:
//
//   ~/Library/Application Support/Logi/LogiPluginService/Applications/
//       Loupedeck40/                        <- device type; see below
//           <bundle id or @_defaultmac>/    <- one folder per app
//               ApplicationInfo.json
//               ApplicationIcon.png
//               Profiles/
//                   <GUID>/
//                       ProfileInfo.json    <- the layout
//                       ActionIcons/*.ict   <- per action icon, JSON + base64 PNG
//
// "Loupedeck40" is this hardware: the service log records
// `Device type: 0x00000400 'Razer Stream Controller'` alongside
// `Device forced to 'Loupedeck40'`, and LoupedeckSettings.ini carries
// `Loupedeck/LastSeenDevice=Loupedeck40`. Other Loupedeck<NN> folders are
// other models (a 7x generation uses a different layout class entirely,
// ProfileLayout7 with pressPages, which this parser deliberately ignores).
//
// The Loupedeck40 layout class is ProfileLayout20, and it lines up with our
// model almost exactly: touchPages are pages of 12 tiles, encoderPages are
// the 6 knobs with a press and a rotate action each. Controls are positional,
// so a control's index in the array is its place on the device; there is no
// id field to decode.

enum LoupedeckImport {

    /// Device type folder for the Razer Stream Controller.
    static let deviceFolder = "Loupedeck40"

    /// Loupedeck's own name for "no specific app", used for the base profile.
    static let defaultAppKey = "@_defaultmac"

    static var applicationsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logi/LogiPluginService/Applications", isDirectory: true)
    }

    static var deviceRoot: URL {
        applicationsRoot.appendingPathComponent(deviceFolder, isDirectory: true)
    }

    /// True when there is anything on this Mac worth offering to import.
    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: deviceRoot.path)
    }

    // MARK: - On disk shapes
    //
    // Every field is optional. This is another application's format, it
    // carries .NET `$type` annotations we ignore, and it varies across
    // Loupedeck versions; a missing or renamed key should degrade the import,
    // never fail it outright.

    struct Profile: Decodable {
        var displayName: String?
        var deviceType: String?
        var applicationName: String?
        var layout: Layout?
        var macroCommands: [MacroCommand]?
        var profileActions: [ProfileCommand]?
    }

    struct Layout: Decodable {
        var deviceType: String?
        var layoutModes: [Mode]?
    }

    struct Mode: Decodable {
        var modeName: String?
        /// Pages of 12 touchscreen tiles.
        var touchPages: [Page]?
        /// Pages of 6 knobs.
        var encoderPages: [Page]?
    }

    struct Page: Decodable {
        var name: String?
        var displayName: String?
        var controls: [Control]?
    }

    /// One physical control's assignment. Position in the page's `controls`
    /// array is the control's position on the device. `fn*` variants are the
    /// second function layer, which we do not have an equivalent for.
    struct Control: Decodable {
        var pressAction: String?
        var rotateAction: String?
        var fnPressAction: String?
        var fnRotateAction: String?
    }

    /// A user built macro. `actions` holds the steps, each an action string.
    struct MacroCommand: Decodable {
        var name: String?
        var displayName: String?
        var description: String?
        var groupName: String?
        var actions: [String]?
    }

    /// A plugin action with saved parameters (Twitch "run commercial for 30s"
    /// and the like). Carries a human label even when the action itself has
    /// no equivalent here.
    struct ProfileCommand: Decodable {
        var name: String?
        var displayName: String?
        var description: String?
        var templateActionName: String?
        var actionParameters: ActionParameters?
    }

    /// Saved parameters for a parameterised action. The inner dictionary also
    /// carries a `$type` entry, which we ignore; every value is a string.
    struct ActionParameters: Decodable {
        var parameters: [String: String]?
    }

    // MARK: - Discovery

    /// One importable profile found on disk.
    struct Discovered: Identifiable, Hashable {
        var id: URL { profileURL }
        /// Directory holding ProfileInfo.json and ActionIcons.
        let profileURL: URL
        /// Loupedeck's app key: a bundle id, or "@_defaultmac" for the base profile.
        let appKey: String
        /// Best available human name for the source app.
        let appName: String
        /// The profile's own name, e.g. "Default".
        let profileName: String
        let modified: Date?

        var isDefaultApp: Bool { appKey == LoupedeckImport.defaultAppKey }
    }

    /// Every profile for this device, newest first. Never throws; an
    /// unreadable entry is skipped rather than failing the whole scan.
    static func scan() -> [Discovered] {
        let fm = FileManager.default
        guard let appDirs = try? fm.contentsOfDirectory(
            at: deviceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [Discovered] = []
        for appDir in appDirs where (try? appDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let appKey = appDir.lastPathComponent
            let profilesDir = appDir.appendingPathComponent("Profiles", isDirectory: true)
            guard let profileDirs = try? fm.contentsOfDirectory(
                at: profilesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for dir in profileDirs {
                let info = dir.appendingPathComponent("ProfileInfo.json")
                guard fm.fileExists(atPath: info.path) else { continue }
                let parsed = try? load(profileAt: dir)
                let modified = (try? info.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                found.append(Discovered(
                    profileURL: dir,
                    appKey: appKey,
                    appName: displayName(forAppKey: appKey, appDir: appDir),
                    profileName: parsed?.displayName ?? dir.lastPathComponent,
                    modified: modified
                ))
            }
        }
        return found.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    /// A readable app name: Loupedeck's placeholder for the base profile, the
    /// installed app's name when the bundle id still resolves, else the raw key.
    private static func displayName(forAppKey key: String, appDir: URL) -> String {
        if key == defaultAppKey { return "All Apps (default)" }
        // Keys for app specific profiles can carry a trailing hash, as in
        // "@_davinciresolve-ade6ee31394b4060".
        let trimmed = key.hasPrefix("@_")
            ? String(key.dropFirst(2)).split(separator: "-").first.map(String.init) ?? key
            : key
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return trimmed.capitalized
    }

    // MARK: - Loading

    static func load(profileAt directory: URL) throws -> Profile {
        let data = try Data(contentsOf: directory.appendingPathComponent("ProfileInfo.json"))
        return try JSONDecoder().decode(Profile.self, from: data)
    }

    /// The mode a profile actually uses. Real profiles carry a single "System"
    /// mode; prefer it by name and fall back to the first present.
    static func primaryMode(of profile: Profile) -> Mode? {
        let modes = profile.layout?.layoutModes ?? []
        return modes.first { $0.modeName == "System" } ?? modes.first
    }
}
