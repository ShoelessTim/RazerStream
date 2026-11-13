import Foundation

/// obs-websocket v5 message envelope pieces RazerStream needs. Every message
/// is {"op": Int, "d": {...}}; see the obs-websocket protocol docs.
public enum OBSOpCode: Int, Sendable {
    case hello = 0
    case identify = 1
    case identified = 2
    case event = 5
    case request = 6
    case requestResponse = 7
}

public enum OBSProtocolError: Error, Equatable, Sendable {
    case malformedMessage
    case unexpectedOpCode(Int)
    case authenticationFailed
    case requestFailed(code: Int, comment: String?)
    case notConnected
    case timedOut
}

/// The server's first message after the socket opens.
public struct OBSHello: Equatable, Sendable {
    public var rpcVersion: Int
    public var challenge: String?
    public var salt: String?

    public var requiresAuth: Bool { challenge != nil && salt != nil }
}

public enum OBSMessages {

    /// Splits a raw message into its op code and its "d" payload.
    public static func envelope(_ data: Data) throws -> (op: Int, payload: [String: Any]) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = object["op"] as? Int,
              let payload = object["d"] as? [String: Any]
        else { throw OBSProtocolError.malformedMessage }
        return (op, payload)
    }

    public static func parseHello(_ data: Data) throws -> OBSHello {
        let (op, d) = try envelope(data)
        guard op == OBSOpCode.hello.rawValue else { throw OBSProtocolError.unexpectedOpCode(op) }
        let auth = d["authentication"] as? [String: Any]
        return OBSHello(
            rpcVersion: d["rpcVersion"] as? Int ?? 1,
            challenge: auth?["challenge"] as? String,
            salt: auth?["salt"] as? String
        )
    }

    /// Identify reply. eventSubscriptions 0: RazerStream polls instead of
    /// subscribing, so a missed event can never leave a light stuck.
    public static func identify(hello: OBSHello, password: String?) throws -> Data {
        var d: [String: Any] = ["rpcVersion": 1, "eventSubscriptions": 0]
        if hello.requiresAuth, let challenge = hello.challenge, let salt = hello.salt {
            guard let password else { throw OBSProtocolError.authenticationFailed }
            d["authentication"] = OBSAuth.authString(password: password, salt: salt, challenge: challenge)
        }
        return try JSONSerialization.data(withJSONObject: ["op": OBSOpCode.identify.rawValue, "d": d])
    }

    public static func request(type: String, id: String, data: [String: Any]? = nil) throws -> Data {
        var d: [String: Any] = ["requestType": type, "requestId": id]
        if let data { d["requestData"] = data }
        return try JSONSerialization.data(withJSONObject: ["op": OBSOpCode.request.rawValue, "d": d])
    }

    /// A parsed RequestResponse: which request it answers and its result.
    public struct Response: Sendable {
        public var requestId: String
        public var result: Result<Data, OBSProtocolError>   // Data is responseData as JSON
    }

    public static func parseResponse(op: Int, payload d: [String: Any]) -> Response? {
        guard op == OBSOpCode.requestResponse.rawValue,
              let id = d["requestId"] as? String,
              let status = d["requestStatus"] as? [String: Any]
        else { return nil }
        if status["result"] as? Bool == true {
            let body = d["responseData"] as? [String: Any] ?? [:]
            let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
            return Response(requestId: id, result: .success(data))
        }
        let code = status["code"] as? Int ?? -1
        return Response(requestId: id, result: .failure(.requestFailed(code: code, comment: status["comment"] as? String)))
    }
}

/// GetStreamStatus and GetRecordStatus responseData; one shape covers both
/// (record has no reconnecting or frame counts, stream has no paused).
public struct OBSOutputStatus: Codable, Equatable, Sendable {
    public var outputActive: Bool
    public var outputReconnecting: Bool?
    public var outputPaused: Bool?
    public var outputDuration: Double?
    public var outputSkippedFrames: Int?
    public var outputTotalFrames: Int?
    public var outputBytes: Double?

    public init(outputActive: Bool, outputReconnecting: Bool? = nil, outputPaused: Bool? = nil,
                outputDuration: Double? = nil, outputSkippedFrames: Int? = nil, outputTotalFrames: Int? = nil,
                outputBytes: Double? = nil) {
        self.outputActive = outputActive
        self.outputReconnecting = outputReconnecting
        self.outputPaused = outputPaused
        self.outputDuration = outputDuration
        self.outputSkippedFrames = outputSkippedFrames
        self.outputTotalFrames = outputTotalFrames
        self.outputBytes = outputBytes
    }
}

/// A request parameter value; keeps request data Sendable across the actor.
public enum OBSParam: Sendable, Equatable {
    case string(String)
    case double(Double)
    case bool(Bool)

    var jsonValue: Any {
        switch self {
        case .string(let v): return v
        case .double(let v): return v
        case .bool(let v):   return v
        }
    }
}

/// GetStats responseData (the parts the deck shows).
public struct OBSStats: Codable, Equatable, Sendable {
    public var cpuUsage: Double?
    public var activeFps: Double?

    public init(cpuUsage: Double? = nil, activeFps: Double? = nil) {
        self.cpuUsage = cpuUsage
        self.activeFps = activeFps
    }
}

/// GetSceneList responseData.
public struct OBSSceneList: Codable, Equatable, Sendable {
    public struct Scene: Codable, Equatable, Sendable {
        public var sceneName: String
        public var sceneIndex: Int
    }
    public var currentProgramSceneName: String?
    public var scenes: [Scene]

    /// Names in the order OBS shows them, top of the Scenes list first. The
    /// server reports the bottom scene as index 0.
    public var namesTopFirst: [String] {
        scenes.sorted { $0.sceneIndex > $1.sceneIndex }.map(\.sceneName)
    }
}
