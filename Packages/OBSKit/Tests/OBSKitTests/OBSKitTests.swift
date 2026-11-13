import XCTest
@testable import OBSKit

final class OBSAuthTests: XCTestCase {
    func testAuthStringMatchesReferenceVector() {
        // Reference computed independently (Python hashlib + base64) with the
        // obs-websocket v5 recipe.
        let auth = OBSAuth.authString(
            password: "supersecretpassword",
            salt: "lM1GncleQOaCu9lT1yeUZhFYnqhsLLP1G5lAGo3ixaI=",
            challenge: "+IxH4CnCiqpX1rM9scsNynZzbOe4KhDeYcTNS3PDaeY="
        )
        XCTAssertEqual(auth, "1Ct943GAT+6YQUUX47Ia/ncufilbe6+oD6lY+5kaCu4=")
    }
}

final class OBSConfigReaderTests: XCTestCase {
    func testJSONWithAuth() {
        let json = #"{"server_enabled":true,"server_port":4460,"auth_required":true,"server_password":"abc123"}"#
        XCTAssertEqual(OBSConfigReader.parseJSON(Data(json.utf8)),
                       OBSServerConfig(enabled: true, port: 4460, password: "abc123"))
    }

    func testJSONAuthOffDropsPassword() {
        let json = #"{"server_enabled":true,"server_port":4455,"auth_required":false,"server_password":"abc123"}"#
        XCTAssertNil(OBSConfigReader.parseJSON(Data(json.utf8))?.password)
    }

    func testJSONWithoutServerKeysIsNotAConfig() {
        XCTAssertNil(OBSConfigReader.parseJSON(Data(#"{"something":"else"}"#.utf8)))
    }

    func testINISectionOnly() {
        let ini = """
        [General]
        ServerPassword=wrong-section

        [OBSWebSocket]
        ServerEnabled=true
        ServerPort=4455
        AuthRequired=true
        ServerPassword=fromini
        """
        XCTAssertEqual(OBSConfigReader.parseINI(ini),
                       OBSServerConfig(enabled: true, port: 4455, password: "fromini"))
    }

    func testINIWithoutSection() {
        XCTAssertNil(OBSConfigReader.parseINI("[General]\nFoo=bar\n"))
    }

    func testLoadPrefersPluginJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let plugin = dir.appendingPathComponent("plugin_config/obs-websocket")
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data(#"{"server_port":4455,"auth_required":true,"server_password":"json"}"#.utf8)
            .write(to: plugin.appendingPathComponent("config.json"))
        try "[OBSWebSocket]\nServerPassword=ini\n".write(to: dir.appendingPathComponent("global.ini"), atomically: true, encoding: .utf8)

        XCTAssertEqual(OBSConfigReader.load(obsDirectory: dir)?.password, "json")
    }

    func testLoadMissingDirectoryIsNil() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNil(OBSConfigReader.load(obsDirectory: dir))
    }
}

final class OBSMessagesTests: XCTestCase {
    func testParseHelloWithAuth() throws {
        let hello = try OBSMessages.parseHello(Data(#"{"op":0,"d":{"obsWebSocketVersion":"5.5.0","rpcVersion":1,"authentication":{"challenge":"c","salt":"s"}}}"#.utf8))
        XCTAssertTrue(hello.requiresAuth)
        XCTAssertEqual(hello.challenge, "c")
    }

    func testIdentifyWithoutAuth() throws {
        let hello = OBSHello(rpcVersion: 1, challenge: nil, salt: nil)
        let object = try JSONSerialization.jsonObject(with: try OBSMessages.identify(hello: hello, password: nil)) as? [String: Any]
        XCTAssertEqual(object?["op"] as? Int, 1)
        XCTAssertNil((object?["d"] as? [String: Any])?["authentication"])
    }

    func testIdentifyNeedsPasswordWhenAuthRequired() {
        let hello = OBSHello(rpcVersion: 1, challenge: "c", salt: "s")
        XCTAssertThrowsError(try OBSMessages.identify(hello: hello, password: nil))
    }

    func testParseSuccessfulStreamStatus() throws {
        let raw = #"{"op":7,"d":{"requestType":"GetStreamStatus","requestId":"rs-1","requestStatus":{"result":true,"code":100},"responseData":{"outputActive":true,"outputReconnecting":false,"outputSkippedFrames":3,"outputTotalFrames":600,"outputDuration":12000}}}"#
        let (op, payload) = try OBSMessages.envelope(Data(raw.utf8))
        let response = try XCTUnwrap(OBSMessages.parseResponse(op: op, payload: payload))
        XCTAssertEqual(response.requestId, "rs-1")
        let status = try JSONDecoder().decode(OBSOutputStatus.self, from: try response.result.get())
        XCTAssertTrue(status.outputActive)
        XCTAssertEqual(status.outputSkippedFrames, 3)
    }

    func testParseFailedRequest() throws {
        let raw = #"{"op":7,"d":{"requestType":"X","requestId":"rs-2","requestStatus":{"result":false,"code":204,"comment":"nope"}}}"#
        let (op, payload) = try OBSMessages.envelope(Data(raw.utf8))
        let response = try XCTUnwrap(OBSMessages.parseResponse(op: op, payload: payload))
        XCTAssertEqual(response.result.failureValue, .requestFailed(code: 204, comment: "nope"))
    }
}

final class OBSLightsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000)

    func live(stream: OBSOutputStatus?, record: OBSOutputStatus? = nil, age: TimeInterval = 0) -> OBSSnapshot {
        OBSSnapshot(connection: .connected, stream: stream, record: record, lastUpdate: now.addingTimeInterval(-age))
    }

    func testConnectionLight() {
        XCTAssertEqual(OBSLights.light(for: .connection, in: live(stream: nil), at: now), .green)
        XCTAssertEqual(OBSLights.light(for: .connection, in: live(stream: nil, age: 10), at: now), .amber)
        XCTAssertEqual(OBSLights.light(for: .connection, in: OBSSnapshot(connection: .notRunning), at: now), .red)
        XCTAssertEqual(OBSLights.light(for: .connection, in: OBSSnapshot(connection: .authFailed), at: now), .red)
    }

    func testStreamLight() {
        XCTAssertEqual(OBSLights.light(for: .stream, in: live(stream: OBSOutputStatus(outputActive: true, outputReconnecting: false)), at: now), .green)
        XCTAssertEqual(OBSLights.light(for: .stream, in: live(stream: OBSOutputStatus(outputActive: true, outputReconnecting: true)), at: now), .amber)
        XCTAssertEqual(OBSLights.light(for: .stream, in: live(stream: OBSOutputStatus(outputActive: false)), at: now), .off)
    }

    func testRecordLight() {
        let idle = OBSOutputStatus(outputActive: false)
        XCTAssertEqual(OBSLights.light(for: .record, in: live(stream: idle, record: OBSOutputStatus(outputActive: true, outputPaused: false)), at: now), .green)
        XCTAssertEqual(OBSLights.light(for: .record, in: live(stream: idle, record: OBSOutputStatus(outputActive: true, outputPaused: true)), at: now), .amber)
    }

    func testStaleDataNeverShowsGreen() {
        // Was live and healthy, but OBS stopped answering: amber, not green.
        let stale = live(stream: OBSOutputStatus(outputActive: true, outputReconnecting: false), age: 10)
        XCTAssertEqual(OBSLights.light(for: .stream, in: stale, at: now), .amber)
        var gone = stale
        gone.connection = .notRunning
        XCTAssertEqual(OBSLights.light(for: .stream, in: gone, at: now), .amber)
        XCTAssertEqual(OBSLights.light(for: .record, in: gone, at: now), .amber)
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

final class OBSPageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10_000)

    func liveSnapshot(skipped: Int = 0, total: Int = 0, micMuted: Bool = false) -> OBSSnapshot {
        var s = OBSSnapshot(connection: .connected,
                            stream: OBSOutputStatus(outputActive: true, outputReconnecting: false,
                                                    outputDuration: 3_725_000, outputSkippedFrames: skipped,
                                                    outputTotalFrames: total),
                            record: OBSOutputStatus(outputActive: false), lastUpdate: now)
        s.micMuted = micMuted
        return s
    }

    func testSceneListTopFirst() throws {
        let raw = #"{"currentProgramSceneName":"Cam","scenes":[{"sceneName":"BRB","sceneIndex":0},{"sceneName":"Screen","sceneIndex":1},{"sceneName":"Cam","sceneIndex":2}]}"#
        let list = try JSONDecoder().decode(OBSSceneList.self, from: Data(raw.utf8))
        XCTAssertEqual(list.namesTopFirst, ["Cam", "Screen", "BRB"])
    }

    func testGoLiveFaceShowsUptimeWhenLive() {
        let face = OBSFaces.face(for: .goLive, in: liveSnapshot(), at: now)
        XCTAssertEqual(face.value, "1:02:05")
    }

    func testEveryTileSaysNoOBSWhenStale() {
        var stale = liveSnapshot()
        stale.lastUpdate = now.addingTimeInterval(-30)
        for role in [OBSTileRole.goLive, .record, .scene(0), .mic, .bitrate, .dropped, .cpu, .fps] {
            XCTAssertEqual(OBSFaces.face(for: role, in: stale, at: now).value, "NO OBS")
        }
    }

    func testSceneFaceMarksOnAir() {
        var s = liveSnapshot()
        s.scenes = ["Cam", "Screen"]
        s.currentScene = "Screen"
        XCTAssertEqual(OBSFaces.face(for: .scene(1), in: s, at: now).title, "ON AIR")
        XCTAssertEqual(OBSFaces.face(for: .scene(0), in: s, at: now).title, "SCENE 1")
        XCTAssertEqual(OBSFaces.face(for: .scene(5), in: s, at: now).value, "none")
    }

    func testMicLightRedOnlyWhenMutedLive() {
        XCTAssertEqual(OBSLights.light(for: .mic, in: liveSnapshot(micMuted: true), at: now), .red)
        var idle = liveSnapshot(micMuted: true)
        idle.stream = OBSOutputStatus(outputActive: false)
        XCTAssertEqual(OBSLights.light(for: .mic, in: idle, at: now), .amber)
        XCTAssertEqual(OBSLights.light(for: .mic, in: liveSnapshot(), at: now), .green)
    }

    func testBitrate() {
        let kbps = OBSRates.kbps(fromBytes: 0, at: now, toBytes: 750_000, at: now.addingTimeInterval(1))
        XCTAssertEqual(kbps ?? 0, 6000, accuracy: 0.1)
        XCTAssertNil(OBSRates.kbps(fromBytes: 10, at: now, toBytes: 5, at: now.addingTimeInterval(1)))
    }

    func testStreamDropAlertsButEndDoesNot() {
        var tracker = OBSAlertTracker()
        XCTAssertEqual(tracker.update(liveSnapshot(), at: now), [])
        var stopped = liveSnapshot()
        stopped.stream = OBSOutputStatus(outputActive: false)
        XCTAssertEqual(tracker.update(stopped, at: now.addingTimeInterval(1)), [.streamDropped])

        var ended = OBSAlertTracker()
        _ = ended.update(liveSnapshot(), at: now)
        ended.noteUserEndedStream(at: now)
        XCTAssertEqual(ended.update(stopped, at: now.addingTimeInterval(1)), [])
    }

    func testOBSGoingSilentWhileLiveAlerts() {
        var tracker = OBSAlertTracker()
        _ = tracker.update(liveSnapshot(), at: now)
        XCTAssertEqual(tracker.update(liveSnapshot(), at: now.addingTimeInterval(30)), [.streamDropped])
    }

    func testFramesDroppingAfterWindow() {
        var tracker = OBSAlertTracker()
        var alerts: [OBSAlert] = []
        for second in 0...10 {
            let t = now.addingTimeInterval(Double(second))
            var s = liveSnapshot(skipped: second * 6, total: second * 60)   // 10% dropped
            s.lastUpdate = t
            alerts += tracker.update(s, at: t)
        }
        XCTAssertEqual(alerts, [.framesDropping])
    }

    func testMicMutedReminderEveryMinute() {
        var tracker = OBSAlertTracker()
        var alerts: [OBSAlert] = []
        for second in stride(from: 0, through: 125, by: 5) {
            let t = now.addingTimeInterval(Double(second))
            var s = liveSnapshot(micMuted: true)
            s.lastUpdate = t
            alerts += tracker.update(s, at: t)
        }
        XCTAssertEqual(alerts, [.micMutedWhileLive, .micMutedWhileLive])
    }
}

final class OBSPreflightTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 20_000)

    func ready() -> OBSSnapshot {
        var s = OBSSnapshot(connection: .connected, stream: OBSOutputStatus(outputActive: false),
                            record: OBSOutputStatus(outputActive: false), lastUpdate: now)
        s.micInput = "Mic/Aux"
        s.micMuted = false
        s.scenes = ["Cam", "Screen"]
        return s
    }

    func testAllGreen() {
        let result = OBSPreflight.evaluate(ready(), streamKeySet: true, freeDiskGB: 200, at: now)
        XCTAssertTrue(result.allPassed)
        XCTAssertEqual(OBSPreflight.face(running: false, result: result).value, "ALL GREEN")
        XCTAssertEqual(OBSPreflight.goLiveHoldSeconds(after: result), 1)
    }

    func testFailuresNameTheProblemAndLengthenTheHold() {
        var s = ready()
        s.micMuted = true
        let result = OBSPreflight.evaluate(s, streamKeySet: false, freeDiskGB: 3, at: now)
        XCTAssertEqual(result.failures.map(\.item), [.mic, .streamKey, .disk])
        XCTAssertEqual(OBSPreflight.face(running: false, result: result).value, "MIC MUTED +2")
        XCTAssertEqual(OBSPreflight.goLiveHoldSeconds(after: result), 3)
    }

    func testUnknownsFail() {
        let result = OBSPreflight.evaluate(OBSSnapshot(), streamKeySet: nil, freeDiskGB: nil, at: now)
        XCTAssertEqual(result.failures.count, OBSPreflightCheck.Item.allCases.count)
        XCTAssertEqual(result.checks.first?.detail, "NO OBS")
    }

    func testNeverRunIsNormalHold() {
        XCTAssertEqual(OBSPreflight.goLiveHoldSeconds(after: nil), 1)
        XCTAssertEqual(OBSPreflight.face(running: false, result: nil).value, "PREFLIGHT")
    }
}
