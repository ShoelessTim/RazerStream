import Foundation

/// One PREFLIGHT check and how it came out.
public struct OBSPreflightCheck: Equatable, Sendable {
    public enum Item: String, CaseIterable, Sendable {
        case obs        // OBS running and answering
        case mic        // Mic/Aux input exists and is not muted
        case scenes     // at least one scene to show
        case streamKey  // a stream key is set
        case disk       // room on the Mac for a recording
    }

    public var item: Item
    public var passed: Bool
    public var detail: String   // short, fits on a tile

    public init(item: Item, passed: Bool, detail: String) {
        self.item = item
        self.passed = passed
        self.detail = detail
    }
}

/// The result of one PREFLIGHT run.
public struct OBSPreflightResult: Equatable, Sendable {
    public var checks: [OBSPreflightCheck]
    public var ranAt: Date

    public init(checks: [OBSPreflightCheck], ranAt: Date) {
        self.checks = checks
        self.ranAt = ranAt
    }

    public var failures: [OBSPreflightCheck] { checks.filter { !$0.passed } }
    public var allPassed: Bool { failures.isEmpty }
}

public enum OBSPreflight {
    /// Free space below this is a red disk check (an hour of 1080p60 is roughly 5 to 10 GB).
    public static let minimumFreeGB: Double = 10

    /// Runs every check against what is known right now. `streamKeySet` and
    /// `freeDiskGB` are nil when they could not be read, which counts as a fail:
    /// PREFLIGHT only passes what it actually confirmed.
    public static func evaluate(_ s: OBSSnapshot, streamKeySet: Bool?, freeDiskGB: Double?, at now: Date) -> OBSPreflightResult {
        let fresh = s.isFresh(at: now)
        var checks: [OBSPreflightCheck] = []

        checks.append(OBSPreflightCheck(
            item: .obs, passed: fresh,
            detail: fresh ? "OBS OK" : (s.connection == .authFailed ? "OBS PASSWORD" : "NO OBS")))

        let micOK = fresh && s.micInput != nil && s.micMuted == false
        let micDetail: String
        if s.micInput == nil { micDetail = "NO MIC" }
        else if s.micMuted == true { micDetail = "MIC MUTED" }
        else { micDetail = micOK ? "MIC OK" : "MIC ?" }
        checks.append(OBSPreflightCheck(item: .mic, passed: micOK, detail: micDetail))

        let scenesOK = fresh && !s.scenes.isEmpty
        checks.append(OBSPreflightCheck(item: .scenes, passed: scenesOK, detail: scenesOK ? "\(s.scenes.count) SCENES" : "NO SCENES"))

        let keyOK = streamKeySet == true
        checks.append(OBSPreflightCheck(item: .streamKey, passed: keyOK, detail: keyOK ? "KEY OK" : "NO KEY"))

        let diskOK = (freeDiskGB ?? 0) >= minimumFreeGB
        let diskDetail = freeDiskGB.map { "\(Int($0)) GB FREE" } ?? "DISK ?"
        checks.append(OBSPreflightCheck(item: .disk, passed: diskOK, detail: diskOK ? diskDetail : "LOW DISK"))

        return OBSPreflightResult(checks: checks, ranAt: now)
    }

    /// How long GO LIVE must be held: one second normally, three when the
    /// last PREFLIGHT found a problem (a deliberate override, not a brush).
    public static func goLiveHoldSeconds(after result: OBSPreflightResult?) -> Double {
        guard let result, !result.allPassed else { return 1 }
        return 3
    }

    /// The PREFLIGHT tile's face.
    public static func face(running: Bool, result: OBSPreflightResult?) -> OBSFace {
        if running { return OBSFace(title: "PREFLIGHT", value: "CHECKING", colorHex: OBSFaces.warn) }
        guard let result else { return OBSFace(title: "tap to check", value: "PREFLIGHT", colorHex: OBSFaces.neutral) }
        if result.allPassed { return OBSFace(title: "PREFLIGHT", value: "ALL GREEN", colorHex: OBSFaces.good) }
        let first = result.failures[0].detail
        let more = result.failures.count > 1 ? " +\(result.failures.count - 1)" : ""
        return OBSFace(title: "PREFLIGHT", value: first + more, colorHex: OBSFaces.bad)
    }
}
