import AppKit
import Foundation

enum MusicPlaybackState: String, Equatable, Sendable {
    case notRunning
    case unavailable
    case stopped
    case paused
    case playing
}

struct MusicNowPlaying: Equatable, Sendable {
    var state: MusicPlaybackState
    var artist: String
    var title: String

    static let notRunning = MusicNowPlaying(state: .notRunning, artist: "", title: "")
}

@MainActor
enum MusicNowPlayingProvider {
    private static let bundleIdentifier = "com.apple.Music"
    private static let separator = "\u{1F}"

    static func current() -> MusicNowPlaying {
        guard !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty else {
            return .notRunning
        }

        let source = """
        tell application id "com.apple.Music"
            set playbackState to (player state as text)
            if playbackState is "stopped" then return playbackState
            set trackTitle to name of current track
            set trackArtist to artist of current track
            return playbackState & (ASCII character 31) & trackArtist & (ASCII character 31) & trackTitle
        end tell
        """

        var error: NSDictionary?
        guard let value = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else {
            return MusicNowPlaying(state: .unavailable, artist: "", title: "")
        }

        let fields = value.components(separatedBy: separator)
        let state: MusicPlaybackState
        switch fields.first?.lowercased() {
        case "playing", "fast forwarding", "rewinding": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }
        return MusicNowPlaying(
            state: state,
            artist: fields.count > 1 ? fields[1] : "",
            title: fields.count > 2 ? fields[2] : ""
        )
    }
}
