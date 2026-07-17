import Foundation

// MARK: - Actions a control can trigger

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
    case gotoPage(Int)                // jump to page index
    case nextPage
    case prevPage
    case showApp                      // bring RazerStream front and center

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
        case .gotoPage(let p):      return "Go to page \(p + 1)"
        case .nextPage:             return "Next page"
        case .prevPage:             return "Previous page"
        case .showApp:              return "Show RazerStream"
        }
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

    var displayName: String {
        switch self {
        case .none:  return "None"
        case .clock: return "Clock"
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
    var action: ControlAction = .none
    var releaseAction: ControlAction = .none   // toggle-off / momentary-release
    var mode: ControlMode = .tap

    init(label: String = "", colorHex: String = "333333", sfSymbol: String? = nil,
         altSymbol: String? = nil, imagePath: String? = nil, iconTint: Bool = false,
         liveContent: LiveContent = .none,
         action: ControlAction = .none, releaseAction: ControlAction = .none,
         mode: ControlMode = .tap) {
        self.label = label
        self.colorHex = colorHex
        self.sfSymbol = sfSymbol
        self.altSymbol = altSymbol
        self.imagePath = imagePath
        self.iconTint = iconTint
        self.liveContent = liveContent
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
        action = try c.decodeIfPresent(ControlAction.self, forKey: .action) ?? .none
        releaseAction = try c.decodeIfPresent(ControlAction.self, forKey: .releaseAction) ?? .none
        mode = try c.decodeIfPresent(ControlMode.self, forKey: .mode) ?? .tap
    }
}

struct KnobConfig: Codable, Equatable {
    var label: String = ""
    var sfSymbol: String? = nil
    var clockwise: ControlAction = .none
    var counterClockwise: ControlAction = .none
    var press: ControlAction = .none
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
