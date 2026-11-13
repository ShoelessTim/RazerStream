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
    public var lastUpdate: Date?   // last successful poll

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
}

/// What a status LED can be told to track.
public enum OBSIndicator: String, Codable, CaseIterable, Hashable, Sendable {
    case connection
    case stream
    case record

    public var displayName: String {
        switch self {
        case .connection: return "OBS connected"
        case .stream:     return "OBS streaming"
        case .record:     return "OBS recording"
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
    /// stream and record go amber (unknown), never their last known color,
    /// so the deck can never show a stale "all good".
    public static func light(for indicator: OBSIndicator, in snapshot: OBSSnapshot, at now: Date) -> OBSLight {
        let fresh = snapshot.isFresh(at: now)

        switch indicator {
        case .connection:
            switch snapshot.connection {
            case .connected:              return fresh ? .green : .amber
            case .connecting:             return .amber
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
        }
    }
}
