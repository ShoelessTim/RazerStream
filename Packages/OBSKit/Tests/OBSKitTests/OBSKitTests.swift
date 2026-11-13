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
