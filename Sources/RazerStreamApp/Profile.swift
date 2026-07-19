import Foundation

// MARK: - Actions a control can trigger

/// One step in a multi-action macro. Runs `action`, then waits `delayAfterMs`
/// before the next step (the wait after the last step is ignored). Nested
/// `.sequence` actions are flattened at play time; the editor never offers
/// Macro as a step type, so users cannot build trees by accident.
struct MacroStep: Codable, Equatable, Identifiable {
    var id: UUID
    var action: ControlAction
    /// Milliseconds to wait after this step before the next one. 0 means
    /// fire the next step immediately. A small value (50 to 100) is typical
    /// between keystrokes so the frontmost app can process each chord.
    var delayAfterMs: UInt16

    init(id: UUID = UUID(), action: ControlAction = .none, delayAfterMs: UInt16 = 100) {
        self.id = id
        self.action = action
        self.delayAfterMs = delayAfterMs
    }

    // Older encodings won't have id; generate one on load so ForEach works.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        action = try c.decodeIfPresent(ControlAction.self, forKey: .action) ?? .none
        delayAfterMs = try c.decodeIfPresent(UInt16.self, forKey: .delayAfterMs) ?? 100
    }

    private enum CodingKeys: String, CodingKey {
        case id, action, delayAfterMs
    }
}

enum ControlAction: Codable, Equatable {
    case none
    case launchApp(path: String)
    case openURL(String)
    case shellCommand(String)
    case appleScript(String)
    case keystroke(String)            // e.g. "cmd+shift+k", "f5", "space"
    case mediaPlayPause
    case mediaNext
    case mediaPrevious
    case volumeUp
    case volumeDown
    case volumeMute
    case brightnessUp                 // steps the device screen brightness
    case brightnessDown
    case ledBrightnessUp              // steps the 7 configurable button LEDs
    case ledBrightnessDown
    case bothBrightnessUp             // steps screen and button LED brightness together
    case bothBrightnessDown
    case gotoPage(Int)                // jump to page index
    case nextPage
    case prevPage
    case showApp                      // bring RazerStream front and center
    /// Ordered multi-action macro: each step is any non-macro ControlAction
    /// plus an optional delay after it. First real general "one control does
    /// many things" path (Screen + LED Brightness was a dedicated special case).
    case sequence([MacroStep])

    var displayName: String {
        switch self {
        case .none:                 return "None"
        case .launchApp(let path):  return "Open \((path as NSString).lastPathComponent)"
        case .openURL(let url):     return "Open \(url)"
        case .shellCommand:         return "Shell command"
        case .appleScript:          return "AppleScript"
        case .keystroke(let k):     return "Keys: \(k)"
        case .mediaPlayPause:       return "Play / Pause"
        case .mediaNext:            return "Next Track"
        case .mediaPrevious:        return "Previous Track"
        case .volumeUp:             return "Volume +"
        case .volumeDown:           return "Volume −"
        case .volumeMute:           return "Mute"
        case .brightnessUp:         return "Brightness +"
        case .brightnessDown:       return "Brightness −"
        case .ledBrightnessUp:      return "Button LED Brightness +"
        case .ledBrightnessDown:    return "Button LED Brightness −"
        case .bothBrightnessUp:     return "Brightness (Screen + LEDs) +"
        case .bothBrightnessDown:   return "Brightness (Screen + LEDs) −"
        case .gotoPage(let p):      return "Go to page \(p + 1)"
        case .nextPage:             return "Next page"
        case .prevPage:             return "Previous page"
        case .showApp:              return "Show RazerStream"
        case .sequence(let steps):
            let n = steps.count
            return n == 1 ? "Macro (1 step)" : "Macro (\(n) steps)"
        }
    }

    /// True when this is a multi-step macro (possibly empty).
    var isSequence: Bool {
        if case .sequence = self { return true }
        return false
    }
}

// MARK: - Control behavior modes

enum ControlMode: Codable, Equatable {
    case tap                 // fire action on press (default)
    case toggle              // alternate: action (on) / releaseAction (off), visual state
    case momentary           // action on press, releaseAction on release
    case shiftPage(Int)      // hold: show page N; release: return
}

// MARK: - Live tile content

// A tile can show self-updating content instead of a static label/icon; the
// clock is the first one. More kinds (now playing, CPU meter) can be added
// here without touching the storage format again.
enum LiveContent: Codable, Equatable {
    case none
    case clock
    case systemMeter
    case diskSpace     // free space on a chosen volume; see *.diskSpaceVolume

    var displayName: String {
        switch self {
        case .none:        return "None"
        case .clock:       return "Clock"
        case .systemMeter: return "CPU / RAM"
        case .diskSpace:   return "Disk Space"
        }
    }
}

// MARK: - Per-control configuration

struct TileConfig: Codable, Equatable {
    var label: String = ""
    var colorHex: String = "333333"
    var sfSymbol: String? = nil       // SF Symbols icon name (built-in library)
    var altSymbol: String? = nil      // icon shown while a toggle is ON
    var imagePath: String? = nil      // custom image file (overrides symbol)
    var iconTint: Bool = false        // tint the image white; for mono pack SVGs
    var liveContent: LiveContent = .none   // self-updating content; overrides label/icon
    var diskSpaceVolume: String = "/"      // which mounted volume, when liveContent == .diskSpace
    var action: ControlAction = .none
    var releaseAction: ControlAction = .none   // toggle-off / momentary-release
    var mode: ControlMode = .tap

    init(label: String = "", colorHex: String = "333333", sfSymbol: String? = nil,
         altSymbol: String? = nil, imagePath: String? = nil, iconTint: Bool = false,
         liveContent: LiveContent = .none, diskSpaceVolume: String = "/",
         action: ControlAction = .none, releaseAction: ControlAction = .none,
         mode: ControlMode = .tap) {
        self.label = label
        self.colorHex = colorHex
        self.sfSymbol = sfSymbol
        self.altSymbol = altSymbol
        self.imagePath = imagePath
        self.iconTint = iconTint
        self.liveContent = liveContent
        self.diskSpaceVolume = diskSpaceVolume
        self.action = action
        self.releaseAction = releaseAction
        self.mode = mode
    }

    // Tolerant decoding so profiles saved by older builds keep loading
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "333333"
        sfSymbol = try c.decodeIfPresent(String.self, forKey: .sfSymbol)
        altSymbol = try c.decodeIfPresent(String.self, forKey: .altSymbol)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        iconTint = try c.decodeIfPresent(Bool.self, forKey: .iconTint) ?? false
        liveContent = try c.decodeIfPresent(LiveContent.self, forKey: .liveContent) ?? .none
        diskSpaceVolume = try c.decodeIfPresent(String.self, forKey: .diskSpaceVolume) ?? "/"
        action = try c.decodeIfPresent(ControlAction.self, forKey: .action) ?? .none
        releaseAction = try c.decodeIfPresent(ControlAction.self, forKey: .releaseAction) ?? .none
        mode = try c.decodeIfPresent(ControlMode.self, forKey: .mode) ?? .tap
    }
}

struct KnobConfig: Codable, Equatable {
    var label: String = ""
    var sfSymbol: String? = nil
    var imagePath: String? = nil      // custom image file (overrides symbol)
    var iconTint: Bool = false        // tint the image white; for mono pack SVGs
    var liveContent: LiveContent = .none   // self-updating content; overrides label/icon
    var diskSpaceVolume: String = "/"      // which mounted volume, when liveContent == .diskSpace
    var clockwise: ControlAction = .none
    var counterClockwise: ControlAction = .none
    var press: ControlAction = .none

    init(label: String = "", sfSymbol: String? = nil, imagePath: String? = nil,
         iconTint: Bool = false, liveContent: LiveContent = .none, diskSpaceVolume: String = "/",
         clockwise: ControlAction = .none, counterClockwise: ControlAction = .none,
         press: ControlAction = .none) {
        self.label = label
        self.sfSymbol = sfSymbol
        self.imagePath = imagePath
        self.iconTint = iconTint
        self.liveContent = liveContent
        self.diskSpaceVolume = diskSpaceVolume
        self.clockwise = clockwise
        self.counterClockwise = counterClockwise
        self.press = press
    }

    // Tolerant decoding so profiles saved by older builds keep loading
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        sfSymbol = try c.decodeIfPresent(String.self, forKey: .sfSymbol)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        iconTint = try c.decodeIfPresent(Bool.self, forKey: .iconTint) ?? false
        liveContent = try c.decodeIfPresent(LiveContent.self, forKey: .liveContent) ?? .none
        diskSpaceVolume = try c.decodeIfPresent(String.self, forKey: .diskSpaceVolume) ?? "/"
        clockwise = try c.decodeIfPresent(ControlAction.self, forKey: .clockwise) ?? .none
        counterClockwise = try c.decodeIfPresent(ControlAction.self, forKey: .counterClockwise) ?? .none
        press = try c.decodeIfPresent(ControlAction.self, forKey: .press) ?? .none
    }
}

struct ButtonConfig: Codable, Equatable {
    var action: ControlAction = .none
    var releaseAction: ControlAction = .none
    var mode: ControlMode = .tap
    var ledHex: String = "000000"     // LED color; button 0 is the status light

    init(action: ControlAction = .none, releaseAction: ControlAction = .none,
         mode: ControlMode = .tap, ledHex: String = "000000") {
        self.action = action
        self.releaseAction = releaseAction
        self.mode = mode
        self.ledHex = ledHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decodeIfPresent(ControlAction.self, forKey: .action) ?? .none
        releaseAction = try c.decodeIfPresent(ControlAction.self, forKey: .releaseAction) ?? .none
        mode = try c.decodeIfPresent(ControlMode.self, forKey: .mode) ?? .tap
        ledHex = try c.decodeIfPresent(String.self, forKey: .ledHex) ?? "000000"
    }
}

// MARK: - Page: one full device layout

struct Page: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String = "Page"
    var tiles: [TileConfig] = Array(repeating: TileConfig(), count: 12)
    var knobs: [KnobConfig] = Array(repeating: KnobConfig(), count: 6)
    var buttons: [ButtonConfig] = Array(repeating: ButtonConfig(), count: 8)
}

// MARK: - Profile: a set of pages + device settings

struct Profile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String = "Default"
    var pages: [Page] = [Page(name: "Page 1")]
    var brightness: UInt8 = 8
    var ledBrightness: UInt8 = 10   // 0...10, matching screen brightness's convention; the 7 configurable button LEDs are scaled by this fraction of their configured color

    // App-switching: which page to show automatically when a given app
    // becomes frontmost. Keyed by bundle identifier rather than app name,
    // since names can collide or change; UUID stored as a string because
    // dictionary keys must be Codable-friendly and JSON object keys are
    // always strings anyway.
    var appSwitchingEnabled: Bool = false
    var appPageMappings: [String: String] = [:]   // bundle ID -> Page.id.uuidString

    // A knob can be pinned so its config is shared across every page instead
    // of each page having its own; `knobIsGlobal[i]` gates whether knob i
    // reads/writes `globalKnobs[i]` instead of `pages[current].knobs[i]`.
    // Lives on Profile (like brightness), not Page, since "same on every
    // page" only means something at the profile level.
    var globalKnobs: [KnobConfig] = Array(repeating: KnobConfig(), count: 6)
    var knobIsGlobal: [Bool] = Array(repeating: false, count: 6)

    init(id: UUID = UUID(), name: String = "Default", pages: [Page] = [Page(name: "Page 1")],
         brightness: UInt8 = 8, ledBrightness: UInt8 = 10, appSwitchingEnabled: Bool = false,
         appPageMappings: [String: String] = [:],
         globalKnobs: [KnobConfig] = Array(repeating: KnobConfig(), count: 6),
         knobIsGlobal: [Bool] = Array(repeating: false, count: 6)) {
        self.id = id
        self.name = name
        self.pages = pages
        self.brightness = brightness
        self.ledBrightness = ledBrightness
        self.appSwitchingEnabled = appSwitchingEnabled
        self.appPageMappings = appPageMappings
        self.globalKnobs = globalKnobs
        self.knobIsGlobal = knobIsGlobal
    }

    // Tolerant decoding so profiles saved before this feature keep loading;
    // plain auto-synthesized Codable would fail on any field added after
    // the fact, since it decodes non-optional keys rather than defaulting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Default"
        pages = try c.decodeIfPresent([Page].self, forKey: .pages) ?? [Page(name: "Page 1")]
        brightness = try c.decodeIfPresent(UInt8.self, forKey: .brightness) ?? 8
        ledBrightness = try c.decodeIfPresent(UInt8.self, forKey: .ledBrightness) ?? 10
        appSwitchingEnabled = try c.decodeIfPresent(Bool.self, forKey: .appSwitchingEnabled) ?? false
        appPageMappings = try c.decodeIfPresent([String: String].self, forKey: .appPageMappings) ?? [:]
        globalKnobs = try c.decodeIfPresent([KnobConfig].self, forKey: .globalKnobs)
            ?? Array(repeating: KnobConfig(), count: 6)
        knobIsGlobal = try c.decodeIfPresent([Bool].self, forKey: .knobIsGlobal)
            ?? Array(repeating: false, count: 6)
    }
}

// MARK: - Persistence

final class ProfileStore: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfileID: UUID?
    @Published var currentPageIndex: Int = 0

    var activeProfile: Profile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles.first ?? Profile()
    }

    var currentPage: Page {
        let pages = activeProfile.pages
        guard !pages.isEmpty else { return Page() }
        return pages[min(currentPageIndex, pages.count - 1)]
    }

    /// `currentPage` with any globally-pinned knobs substituted in. Use this
    /// (not `currentPage`) wherever a page is actually dispatched to the
    /// device or mirrored in the app window, since a pinned knob's real
    /// config lives in `globalKnobs`, not inside the page itself.
    var resolvedCurrentPage: Page {
        var page = currentPage
        let profile = activeProfile
        for i in page.knobs.indices
        where profile.knobIsGlobal.indices.contains(i) && profile.knobIsGlobal[i]
            && profile.globalKnobs.indices.contains(i) {
            page.knobs[i] = profile.globalKnobs[i]
        }
        return page
    }

    func isKnobGlobal(_ index: Int) -> Bool {
        activeProfile.knobIsGlobal.indices.contains(index) && activeProfile.knobIsGlobal[index]
    }

    /// The knob config that's actually in effect right now for `index`,
    /// whether it comes from the current page or a pinned global slot.
    func knobConfig(_ index: Int) -> KnobConfig {
        let profile = activeProfile
        if isKnobGlobal(index), profile.globalKnobs.indices.contains(index) {
            return profile.globalKnobs[index]
        }
        return currentPage.knobs.indices.contains(index) ? currentPage.knobs[index] : KnobConfig()
    }

    /// Writes a knob's config to wherever it currently lives: the global
    /// slot if pinned, otherwise just the current page.
    func updateKnob(_ index: Int, _ newValue: KnobConfig) {
        if isKnobGlobal(index) {
            updateActive { profile in
                guard profile.globalKnobs.indices.contains(index) else { return }
                profile.globalKnobs[index] = newValue
            }
        } else {
            updateCurrentPage { page in
                guard page.knobs.indices.contains(index) else { return }
                page.knobs[index] = newValue
            }
        }
    }

    /// Pins or unpins a knob. Pinning seeds the global slot from whatever is
    /// on the current page right now, so nothing is lost; unpinning writes
    /// the (possibly since-edited) global value back down into just the
    /// current page, for the same reason.
    func setKnobGlobal(_ index: Int, _ isGlobal: Bool) {
        let pageIdx = currentPageIndex
        updateActive { profile in
            guard profile.knobIsGlobal.indices.contains(index),
                  profile.globalKnobs.indices.contains(index),
                  profile.pages.indices.contains(pageIdx)
            else { return }
            if isGlobal {
                profile.globalKnobs[index] = profile.pages[pageIdx].knobs[index]
            } else {
                profile.pages[pageIdx].knobs[index] = profile.globalKnobs[index]
            }
            profile.knobIsGlobal[index] = isGlobal
        }
    }

    /// Re-derives clockwise/counterClockwise for every knob currently in
    /// Volume or Brightness rotation mode, across every profile, page, and
    /// pinned global slot — called when the handedness setting changes in
    /// Settings > Device, so "consistent across all experiences" actually
    /// holds instead of only affecting knobs edited after the fact.
    func reapplyKnobDirection() {
        func reassign(_ knob: inout KnobConfig) {
            let mode = KnobRotationMode.detect(clockwise: knob.clockwise, counterClockwise: knob.counterClockwise)
            guard mode != .none && mode != .custom else { return }
            let pair = KnobRotationMode.actions(for: mode, clockwiseIncreases: KnobDirection.clockwiseIncreases)
            knob.clockwise = pair.clockwise
            knob.counterClockwise = pair.counterClockwise
        }
        for pIdx in profiles.indices {
            for pageIdx in profiles[pIdx].pages.indices {
                for kIdx in profiles[pIdx].pages[pageIdx].knobs.indices {
                    reassign(&profiles[pIdx].pages[pageIdx].knobs[kIdx])
                }
            }
            for kIdx in profiles[pIdx].globalKnobs.indices {
                reassign(&profiles[pIdx].globalKnobs[kIdx])
            }
        }
        save()
    }

    private var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RazerStream", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    init() {
        load()
        if profiles.isEmpty {
            profiles = [Self.starterProfile()]
            activeProfileID = profiles[0].id
            save()
        }
        if activeProfileID == nil { activeProfileID = profiles.first?.id }
    }

    static func starterProfile() -> Profile {
        var page = Page(name: "Page 1")
        let starterColors = ["8E3B46", "B36A2E", "8F8A2B", "3E7C4F",
                             "2E7C8F", "31518F", "6C3E8F", "8F2E6E",
                             "4A4E69", "22577A", "38A3A5", "57CC99"]
        for i in 0..<page.tiles.count {
            page.tiles[i].label = "\(i)"
            page.tiles[i].colorHex = starterColors[i % starterColors.count]
        }
        var profile = Profile()
        profile.pages = [page]
        return profile
    }

    func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }

        if applyDecoded(data) { return }

        // Migrate v0 format (flat tiles/knobs/buttons on Profile → single page)
        if let old = try? JSONDecoder().decode(OldSavedState.self, from: data) {
            profiles = old.profiles.map { op in
                var page = Page(name: "Page 1")
                page.tiles = op.tiles
                var profile = Profile()
                profile.id = op.id
                profile.name = op.name
                profile.brightness = op.brightness
                profile.pages = [page]
                return profile
            }
            activeProfileID = old.activeProfileID
            save()
            return
        }

        // The file exists but could not be read in any known format. Never
        // silently discard it; the old behaviour returned empty here, and the
        // initializer then overwrote the file with a fresh starter, destroying
        // whatever was there. Instead, preserve the unreadable file for
        // forensics and try to recover from the newest good version snapshot.
        let corruptURL = storeURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: storeURL, to: corruptURL)
        NSLog("profiles.json unreadable; preserved at \(corruptURL.lastPathComponent), attempting version recovery")

        for version in listVersions() {
            if let vData = try? Data(contentsOf: version.url), applyDecoded(vData) {
                NSLog("recovered from version snapshot \(version.url.lastPathComponent)")
                save()
                return
            }
        }
        // Nothing recoverable; leave profiles empty so the initializer creates
        // a starter, but the original file is safe under its .corrupt name.
    }

    private func applyDecoded(_ data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(SavedState.self, from: data) else { return false }
        profiles = decoded.profiles
        activeProfileID = decoded.activeProfileID
        return true
    }

    func save() {
        let state = SavedState(profiles: profiles, activeProfileID: activeProfileID)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: storeURL, options: .atomic)
        snapshotVersion(data)
    }

    func updateActive(_ mutate: (inout Profile) -> Void) {
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        mutate(&profiles[idx])
        save()
    }

    func updateCurrentPage(_ mutate: (inout Page) -> Void) {
        let pageIdx = currentPageIndex
        updateActive { profile in
            guard pageIdx < profile.pages.count else { return }
            mutate(&profile.pages[pageIdx])
        }
    }

    // MARK: page navigation

    func goToPage(_ index: Int) {
        let count = activeProfile.pages.count
        guard count > 0 else { return }
        currentPageIndex = ((index % count) + count) % count
    }

    func addPage() {
        updateActive { $0.pages.append(Page(name: "Page \($0.pages.count + 1)")) }
        currentPageIndex = activeProfile.pages.count - 1
    }

    /// Deletes a page by id regardless of which page is currently selected;
    /// used by the sidebar, where a context menu can target any row.
    func deletePage(_ pageID: Page.ID) {
        guard activeProfile.pages.count > 1 else { return }
        updateActive { profile in
            profile.pages.removeAll { $0.id == pageID }
        }
        currentPageIndex = min(currentPageIndex, activeProfile.pages.count - 1)
    }

    func renamePage(_ pageID: Page.ID, to name: String) {
        updateActive { profile in
            guard let idx = profile.pages.firstIndex(where: { $0.id == pageID }) else { return }
            profile.pages[idx].name = name
        }
    }

    /// Reorders pages themselves (dragging a page row in the sidebar);
    /// distinct from reordering tiles within a page.
    func movePages(fromOffsets: IndexSet, toOffset: Int) {
        let currentID = currentPage.id
        updateActive { $0.pages.move(fromOffsets: fromOffsets, toOffset: toOffset) }
        if let newIdx = activeProfile.pages.firstIndex(where: { $0.id == currentID }) {
            currentPageIndex = newIdx
        }
    }

    /// Moves a tile on the current page from one slot to another; everything
    /// between the two slots shifts to make room, the same way Home Screen
    /// icon rearrangement works. `to` is the tile's final index after the
    /// move, not an insertion-before offset.
    func moveTile(from: Int, to: Int) {
        updateCurrentPage { page in
            guard from != to,
                  page.tiles.indices.contains(from),
                  page.tiles.indices.contains(to)
            else { return }
            let item = page.tiles.remove(at: from)
            page.tiles.insert(item, at: to)
        }
    }

    /// Moves a tile's configuration to a different page (dragged onto that
    /// page's sidebar row). A fixed 12-slot page cannot grow to make room the
    /// way a same-page shift can, so this only completes when the
    /// destination has a genuinely empty slot to land in; otherwise it is a
    /// no-op and nothing on either page is touched. On success the source
    /// slot is cleared, since this is a move, not a copy.
    func moveTile(from sourceIndex: Int, sourcePageID: Page.ID, toPageID destPageID: Page.ID) {
        guard sourcePageID != destPageID else { return }
        updateActive { profile in
            guard let sourcePageIdx = profile.pages.firstIndex(where: { $0.id == sourcePageID }),
                  let destPageIdx = profile.pages.firstIndex(where: { $0.id == destPageID }),
                  profile.pages[sourcePageIdx].tiles.indices.contains(sourceIndex),
                  let emptySlot = profile.pages[destPageIdx].tiles.firstIndex(where: { $0 == TileConfig() })
            else { return }
            let moved = profile.pages[sourcePageIdx].tiles[sourceIndex]
            profile.pages[destPageIdx].tiles[emptySlot] = moved
            profile.pages[sourcePageIdx].tiles[sourceIndex] = TileConfig()
        }
    }

    // MARK: - Version history
    //
    // Apple's own document apps never expose per-keystroke undo across a
    // relaunch; they autosave continuously and let you step back through a
    // browsable version history instead (File > Revert To > Browse All
    // Versions). This is the same idea, sized for a single JSON file: every
    // save snapshots the whole state, "Restore Previous Version" browses
    // those snapshots, and "Duplicate Profile" is the manual named
    // checkpoint (the equivalent of File > Duplicate).

    private var versionsDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RazerStream", isDirectory: true)
            .appendingPathComponent("Versions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Fixed-width, zero-padded fields sort lexicographically in the same
    // order as chronologically, so filenames can be pruned without parsing.
    private static let versionFilenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // A bounded recent-snapshot history rather than true Time Machine style
    // thinning (dense recent, sparse older); simpler, and still covers
    // "I want to step back a few edits" without unbounded disk growth.
    private let maxVersions = 20

    private func snapshotVersion(_ data: Data) {
        let name = Self.versionFilenameFormatter.string(from: Date()) + ".json"
        try? data.write(to: versionsDir.appendingPathComponent(name), options: .atomic)
        pruneVersions()
    }

    private func pruneVersions() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: versionsDir, includingPropertiesForKeys: nil
        )) ?? []
        let newestFirst = files.sorted { $0.lastPathComponent > $1.lastPathComponent }
        if newestFirst.count > maxVersions {
            for url in newestFirst[maxVersions...] {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    struct ProfileVersion: Identifiable, Equatable {
        var id: URL { url }
        let date: Date
        let url: URL
    }

    /// Saved snapshots, newest first.
    func listVersions() -> [ProfileVersion] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: versionsDir, includingPropertiesForKeys: nil
        )) ?? []
        return files.compactMap { url -> ProfileVersion? in
            let stem = url.deletingPathExtension().lastPathComponent
            guard let date = Self.versionFilenameFormatter.date(from: stem) else { return nil }
            return ProfileVersion(date: date, url: url)
        }.sorted { $0.date > $1.date }
    }

    /// Restores profiles and the active profile id from a saved snapshot.
    /// The state right before the restore is snapshotted first, so restoring
    /// can never lose work; the restored state then becomes its own new
    /// save point, the same way restoring from Time Machine behaves.
    func restoreVersion(_ version: ProfileVersion) {
        save()   // snapshot pre-restore state before overwriting anything

        guard let data = try? Data(contentsOf: version.url),
              let decoded = try? JSONDecoder().decode(SavedState.self, from: data)
        else { return }
        profiles = decoded.profiles
        activeProfileID = decoded.activeProfileID
        currentPageIndex = 0
        save()
    }

    /// Explicit named checkpoint; the manual equivalent of File > Duplicate.
    func duplicateProfile(_ id: UUID) {
        guard let original = profiles.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = "\(original.name) copy"
        profiles.append(copy)
        save()
    }

    // MARK: - Native profile export/import (.razerstream files)

    /// Encodes a single profile as a standalone file, separate from the
    /// whole profiles.json store, so it can be shared with someone else or
    /// kept as a backup outside the app's own version history.
    func exportData(for profileID: UUID) -> Data? {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return nil }
        return try? JSONEncoder().encode(profile)
    }

    /// Imports a profile written by exportData(for:). Always gets a fresh
    /// id, so it can never collide with or overwrite an existing profile,
    /// and becomes the active profile so the import is immediately visible.
    @discardableResult
    func importProfile(from data: Data) -> Bool {
        guard var profile = try? JSONDecoder().decode(Profile.self, from: data) else { return false }
        profile.id = UUID()
        if profiles.contains(where: { $0.name == profile.name }) {
            profile.name += " (imported)"
        }
        profiles.append(profile)
        activeProfileID = profile.id
        currentPageIndex = 0
        save()
        return true
    }

    // MARK: - App-switching pages

    func setAppSwitchingEnabled(_ enabled: Bool) {
        updateActive { $0.appSwitchingEnabled = enabled }
    }

    func setAppMapping(bundleID: String, pageID: Page.ID) {
        updateActive { $0.appPageMappings[bundleID] = pageID.uuidString }
    }

    func removeAppMapping(bundleID: String) {
        updateActive { $0.appPageMappings.removeValue(forKey: bundleID) }
    }

    /// The page index mapped to a bundle identifier, if the page still
    /// exists (it may have been deleted since the mapping was made) and
    /// app switching is turned on.
    func pageIndex(forBundleID bundleID: String) -> Int? {
        let profile = activeProfile
        guard profile.appSwitchingEnabled,
              let idString = profile.appPageMappings[bundleID],
              let pageID = UUID(uuidString: idString)
        else { return nil }
        return profile.pages.firstIndex { $0.id == pageID }
    }

    private struct SavedState: Codable {
        var profiles: [Profile]
        var activeProfileID: UUID?
    }

    // v0 shape, for migration
    private struct OldProfile: Codable {
        var id: UUID
        var name: String
        var tiles: [TileConfig]
        var brightness: UInt8
    }
    private struct OldSavedState: Codable {
        var profiles: [OldProfile]
        var activeProfileID: UUID?
    }
}
