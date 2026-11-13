import Foundation

/// How the connection to OBS stands right now.
public enum OBSConnectionState: Equatable, Sendable {
    case notRunning     // nothing answering on the port (OBS closed or server off)
    case connecting
    case authFailed     // OBS answered but refused the password
    case connected
}

/// Everything the deck needs to know about OBS at one moment.
public struct OBSSnapshot: Equatable, Sendable {
    public var connection: OBSConnectionState
    public var stream: OBSOutputStatus?
    public var record: OBSOutputStatus?
    public var lastUpdate: Date?          // last successful poll

    public var scenes: [String] = []      // top of OBS's Scenes list first
    public var currentScene: String?
    public var micInput: String?          // OBS's Mic/Aux 1, by name
    public var desktopInput: String?      // OBS's Desktop Audio 1, by name
    public var micMuted: Bool?
    public var cpuUsage: Double?          // percent, OBS process
    public var activeFps: Double?
    public var bitrateKbps: Double?       // stream upload, computed between polls

    public init(connection: OBSConnectionState = .notRunning, stream: OBSOutputStatus? = nil,
                record: OBSOutputStatus? = nil, lastUpdate: Date? = nil) {
        self.connection = connection
        self.stream = stream
        self.record = record
        self.lastUpdate = lastUpdate
    }

    /// Older than this and the data no longer counts as live.
    public static let staleAfter: TimeInterval = 3

    public func isFresh(at now: Date) -> Bool {
        guard connection == .connected, let lastUpdate else { return false }
        return now.timeIntervalSince(lastUpdate) <= Self.staleAfter
    }

    public var isLive: Bool { stream?.outputActive == true }

    /// Dropped (skipped) frames as a percent of all stream frames so far.
    public var droppedPercent: Double? {
        guard let stream, let total = stream.outputTotalFrames, total > 0 else { return nil }
        return Double(stream.outputSkippedFrames ?? 0) / Double(total) * 100
    }
}

/// What a status LED can be told to track.
public enum OBSIndicator: String, Codable, CaseIterable, Hashable, Sendable {
    case connection
    case stream
    case record
    case mic

    public var displayName: String {
        switch self {
        case .connection: return "OBS connected"
        case .stream:     return "OBS streaming"
        case .record:     return "OBS recording"
        case .mic:        return "OBS mic live"
        }
    }
}

/// Status light colors: green is OK, amber is degraded or unknown, red is down.
public enum OBSLight: Equatable, Sendable {
    case off, green, amber, red

    public var hex: String {
        switch self {
        case .off:   return "000000"
        case .green: return "00E040"
        case .amber: return "FFA000"
        case .red:   return "FF0000"
        }
    }
}

public enum OBSLights {

    /// The color one indicator should show. Rule: if OBS is not answering,
    /// everything but the connection light goes amber (unknown), never its
    /// last known color, so the deck can never show a stale "all good".
    public static func light(for indicator: OBSIndicator, in snapshot: OBSSnapshot, at now: Date) -> OBSLight {
        let fresh = snapshot.isFresh(at: now)

        switch indicator {
        case .connection:
            switch snapshot.connection {
            case .connected:               return fresh ? .green : .amber
            case .connecting:              return .amber
            case .notRunning, .authFailed: return .red
            }

        case .stream:
            guard fresh else { return .amber }
            guard let stream = snapshot.stream, stream.outputActive else { return .off }
            return stream.outputReconnecting == true ? .amber : .green

        case .record:
            guard fresh else { return .amber }
            guard let record = snapshot.record, record.outputActive else { return .off }
            return record.outputPaused == true ? .amber : .green

        case .mic:
            guard fresh else { return .amber }
            guard let muted = snapshot.micMuted else { return .off }
            if !muted { return .green }
            return snapshot.isLive ? .red : .amber   // muted while live is the one that bites
        }
    }
}

// MARK: - Tiles

/// What an OBS tile does and shows. Controls fire on press; readouts only show.
public enum OBSTileRole: Codable, Hashable, Sendable {
    case goLive          // hold to start or end the stream
    case record          // tap to start or stop recording
    case scene(Int)      // tap to switch; slot 0 is the top of OBS's Scenes list
    case mic             // tap to mute or unmute Mic/Aux
    case bitrate
    case dropped
    case cpu
    case fps

    /// Controls that must be held, so a brush of the screen cannot go live or end a stream.
    public var requiresHold: Bool { self == .goLive }

    public var displayName: String {
        switch self {
        case .goLive:          return "GO LIVE / END"
        case .record:          return "Record"
        case .scene(let slot): return "Scene \(slot + 1)"
        case .mic:             return "Mic mute"
        case .bitrate:         return "Bitrate"
        case .dropped:         return "Dropped frames"
        case .cpu:             return "OBS CPU"
        case .fps:             return "FPS"
        }
    }

    var shortTitle: String {
        switch self {
        case .goLive:          return "GO LIVE"
        case .record:          return "REC"
        case .scene(let slot): return "SCENE \(slot + 1)"
        case .mic:             return "MIC"
        case .bitrate:         return "BITRATE"
        case .dropped:         return "DROPPED"
        case .cpu:             return "OBS CPU"
        case .fps:             return "FPS"
        }
    }
}

/// What one OBS tile shows: a small title, a big value, a background color.
public struct OBSFace: Equatable, Sendable {
    public var title: String
    public var value: String
    public var colorHex: String

    public init(title: String, value: String, colorHex: String) {
        self.title = title
        self.value = value
        self.colorHex = colorHex
    }
}

public enum OBSFaces {
    static let neutral = "26282C"
    static let live = "C62828"
    static let good = "1B5E20"
    static let warn = "B26A00"
    static let bad = "B71C1C"
    static let unknown = "4A4A4A"

    public static func face(for role: OBSTileRole, in s: OBSSnapshot, at now: Date) -> OBSFace {
        // OBS silent: say so on every tile rather than show old numbers
        guard s.isFresh(at: now) else {
            let reason = s.connection == .authFailed ? "PASSWORD" : "NO OBS"
            return OBSFace(title: role.shortTitle, value: reason, colorHex: unknown)
        }

        switch role {
        case .goLive:
            if s.isLive {
                let reconnecting = s.stream?.outputReconnecting == true
                return OBSFace(title: reconnecting ? "RECONNECTING" : "LIVE, hold to end",
                               value: duration(s.stream?.outputDuration),
                               colorHex: reconnecting ? warn : live)
            }
            return OBSFace(title: "hold", value: "GO LIVE", colorHex: neutral)

        case .record:
            guard let record = s.record, record.outputActive else {
                return OBSFace(title: "REC", value: "OFF", colorHex: neutral)
            }
            return OBSFace(title: record.outputPaused == true ? "REC PAUSED" : "REC",
                           value: duration(record.outputDuration), colorHex: live)

        case .scene(let slot):
            guard s.scenes.indices.contains(slot) else {
                return OBSFace(title: "SCENE \(slot + 1)", value: "none", colorHex: neutral)
            }
            let name = s.scenes[slot]
            let onAir = name == s.currentScene
            return OBSFace(title: onAir ? "ON AIR" : "SCENE \(slot + 1)", value: name,
                           colorHex: onAir ? good : neutral)

        case .mic:
            guard let muted = s.micMuted else { return OBSFace(title: "MIC", value: "none", colorHex: neutral) }
            if muted { return OBSFace(title: "MIC", value: "MUTED", colorHex: s.isLive ? bad : warn) }
            return OBSFace(title: "MIC", value: "ON", colorHex: good)

        case .bitrate:
            guard s.isLive, let kbps = s.bitrateKbps else {
                return OBSFace(title: "BITRATE", value: "--", colorHex: neutral)
            }
            return OBSFace(title: "BITRATE kbps", value: "\(Int(kbps.rounded()))", colorHex: kbps < 1000 ? warn : good)

        case .dropped:
            guard s.isLive, let pct = s.droppedPercent else {
                return OBSFace(title: "DROPPED", value: "--", colorHex: neutral)
            }
            let color = pct >= 5 ? bad : pct >= 1 ? warn : good
            return OBSFace(title: "DROPPED", value: String(format: "%.1f%%", pct), colorHex: color)

        case .cpu:
            guard let cpu = s.cpuUsage else { return OBSFace(title: "OBS CPU", value: "--", colorHex: neutral) }
            let color = cpu >= 80 ? bad : cpu >= 50 ? warn : good
            return OBSFace(title: "OBS CPU", value: "\(Int(cpu.rounded()))%", colorHex: color)

        case .fps:
            guard let fps = s.activeFps else { return OBSFace(title: "FPS", value: "--", colorHex: neutral) }
            return OBSFace(title: "FPS", value: "\(Int(fps.rounded()))", colorHex: neutral)
        }
    }

    /// h:mm:ss from OBS's millisecond duration.
    static func duration(_ ms: Double?) -> String {
        let total = Int((ms ?? 0) / 1000)
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

// MARK: - Bitrate

public enum OBSRates {
    /// Upload rate in kilobits per second between two byte counts.
    public static func kbps(fromBytes before: Double, at t0: Date, toBytes after: Double, at t1: Date) -> Double? {
        let seconds = t1.timeIntervalSince(t0)
        guard seconds > 0.2, after >= before else { return nil }
        return (after - before) * 8 / 1000 / seconds
    }
}

// MARK: - Haptic alerts

public enum OBSAlert: Equatable, Sendable {
    case streamDropped       // was live, now is not, and nobody pressed END
    case framesDropping      // over 5% of frames dropped across the last 10 seconds
    case micMutedWhileLive   // reminder every 60 seconds
}

/// Turns a stream of snapshots into the alerts the deck should buzz for.
/// Pure and clock-driven so it can be tested without OBS.
public struct OBSAlertTracker: Sendable {
    public static let dropWindow: TimeInterval = 10
    public static let dropThresholdPercent: Double = 5
    public static let micReminderInterval: TimeInterval = 60

    private struct FrameSample: Sendable {
        var time: Date
        var skipped: Int
        var total: Int
    }

    private var wasLive = false
    private var userEndedAt: Date?
    private var frameSamples: [FrameSample] = []
    private var lastFramesAlert: Date?
    private var micMutedSince: Date?

    public init() {}

    /// Call right before sending END, so the stop that follows is not an alarm.
    public mutating func noteUserEndedStream(at now: Date) { userEndedAt = now }

    public mutating func update(_ s: OBSSnapshot, at now: Date) -> [OBSAlert] {
        var alerts: [OBSAlert] = []
        let live = s.isFresh(at: now) && s.isLive

        // Live before; not live now (stopped, or OBS stopped answering), not by END
        if wasLive && !live {
            let intended = userEndedAt.map { now.timeIntervalSince($0) < 15 } ?? false
            if !intended { alerts.append(.streamDropped) }
        }
        wasLive = live

        // Dropped frames over a sliding window, not since the stream began
        if live, let skipped = s.stream?.outputSkippedFrames, let total = s.stream?.outputTotalFrames {
            frameSamples.append(FrameSample(time: now, skipped: skipped, total: total))
            frameSamples.removeAll { now.timeIntervalSince($0.time) > Self.dropWindow }
            if let first = frameSamples.first,
               now.timeIntervalSince(first.time) >= Self.dropWindow * 0.8,
               total > first.total {
                let pct = Double(skipped - first.skipped) / Double(total - first.total) * 100
                let cooledDown = lastFramesAlert.map { now.timeIntervalSince($0) >= Self.dropWindow * 3 } ?? true
                if pct > Self.dropThresholdPercent && cooledDown {
                    alerts.append(.framesDropping)
                    lastFramesAlert = now
                }
            }
        } else {
            frameSamples.removeAll()
        }

        // Muted mic while live: a tick every 60 seconds, the first one a minute in
        if live && s.micMuted == true {
            if let since = micMutedSince {
                if now.timeIntervalSince(since) >= Self.micReminderInterval {
                    alerts.append(.micMutedWhileLive)
                    micMutedSince = now
                }
            } else {
                micMutedSince = now
            }
        } else {
            micMutedSince = nil
        }

        return alerts
    }
}
