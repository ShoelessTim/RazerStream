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
    var artworkData: Data? = nil

    static let notRunning = MusicNowPlaying(state: .notRunning, artist: "", title: "")
}

@MainActor
enum MusicNowPlayingProvider {
    private static let bundleIdentifier = "com.apple.Music"
    private static var cachedArtworkKey = ""
    private static var cachedArtworkData: Data?

    static func current() -> MusicNowPlaying {
        guard !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty else {
            return .notRunning
        }

        let source = """
        tell application id "com.apple.Music"
            set playbackState to (player state as text)
            if playbackState is "stopped" then return {playbackState, "", "", ""}
            set trackTitle to name of current track
            set trackArtist to artist of current track
            try
                set trackKey to (persistent ID of current track) & (ASCII character 31) & trackArtist & (ASCII character 31) & trackTitle
            on error
                set trackKey to trackArtist & (ASCII character 31) & trackTitle
            end try
            return {playbackState, trackArtist, trackTitle, trackKey}
        end tell
        """

        var error: NSDictionary?
        guard let value = NSAppleScript(source: source)?.executeAndReturnError(&error),
              value.numberOfItems >= 4 else {
            return MusicNowPlaying(state: .unavailable, artist: "", title: "")
        }

        let stateValue = value.atIndex(1)?.stringValue?.lowercased()
        let state: MusicPlaybackState
        switch stateValue {
        case "playing", "fast forwarding", "rewinding": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }
        let artist = value.atIndex(2)?.stringValue ?? ""
        let title = value.atIndex(3)?.stringValue ?? ""
        let trackKey = value.atIndex(4)?.stringValue ?? ""
        return MusicNowPlaying(
            state: state,
            artist: artist,
            title: title,
            artworkData: state == .stopped ? nil : artwork(for: trackKey)
        )
    }

    private static func artwork(for trackKey: String) -> Data? {
        guard !trackKey.isEmpty else { return nil }
        if trackKey == cachedArtworkKey { return cachedArtworkData }

        let source = """
        tell application id "com.apple.Music"
            try
                if (count of artworks of current track) is 0 then return missing value
                return raw data of artwork 1 of current track
            on error
                return missing value
            end try
        end tell
        """
        var error: NSDictionary?
        let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
        let data = descriptor?.data
        cachedArtworkKey = trackKey
        cachedArtworkData = data.flatMap { NSImage(data: $0) == nil ? nil : $0 }
        return cachedArtworkData
    }
}
