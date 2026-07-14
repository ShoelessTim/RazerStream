import Foundation

// MARK: - Actions a control can trigger

enum ControlAction: Codable, Equatable {
    case none
    case launchApp(path: String)
    case shellCommand(String)
    case appleScript(String)
    case volumeUp
    case volumeDown
    case volumeMute

    var displayName: String {
        switch self {
        case .none:                 return "None"
        case .launchApp(let path):  return "Open \((path as NSString).lastPathComponent)"
        case .shellCommand:         return "Shell command"
        case .appleScript:          return "AppleScript"
        case .volumeUp:             return "Volume +"
        case .volumeDown:           return "Volume −"
        case .volumeMute:           return "Mute"
        }
    }
}

// MARK: - Per-control configuration

struct TileConfig: Codable, Equatable {
    var label: String = ""
    var colorHex: String = "333333"       // background color of the tile
    var imagePath: String? = nil          // optional image drawn over the background
    var action: ControlAction = .none
}

struct KnobConfig: Codable, Equatable {
    var clockwise: ControlAction = .none
    var counterClockwise: ControlAction = .none
    var press: ControlAction = .none
}

struct ButtonConfig: Codable, Equatable {
    var action: ControlAction = .none
}

// MARK: - Profile

struct Profile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String = "Default"
    var tiles: [TileConfig] = Array(repeating: TileConfig(), count: 12)
    var knobs: [KnobConfig] = Array(repeating: KnobConfig(), count: 6)
    var buttons: [ButtonConfig] = Array(repeating: ButtonConfig(), count: 8)
    var brightness: UInt8 = 8
}

// MARK: - Persistence

final class ProfileStore: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfileID: UUID?

    var activeProfile: Profile {
        get { profiles.first(where: { $0.id == activeProfileID }) ?? profiles.first ?? Profile() }
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
            var p = Profile()
            p.name = "Default"
            // Visible starter tiles so a fresh install shows something on-device
            let starterColors = ["8E3B46", "B36A2E", "8F8A2B", "3E7C4F",
                                 "2E7C8F", "31518F", "6C3E8F", "8F2E6E",
                                 "4A4E69", "22577A", "38A3A5", "57CC99"]
            for i in 0..<p.tiles.count {
                p.tiles[i].label = "\(i)"
                p.tiles[i].colorHex = starterColors[i % starterColors.count]
            }
            profiles = [p]
            activeProfileID = p.id
            save()
        }
        if activeProfileID == nil { activeProfileID = profiles.first?.id }
    }

    func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        profiles = decoded.profiles
        activeProfileID = decoded.activeProfileID
    }

    func save() {
        let state = SavedState(profiles: profiles, activeProfileID: activeProfileID)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    func updateActive(_ mutate: (inout Profile) -> Void) {
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        mutate(&profiles[idx])
        save()
    }

    private struct SavedState: Codable {
        var profiles: [Profile]
        var activeProfileID: UUID?
    }
}
