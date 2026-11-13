import Foundation

/// A minimal obs-websocket v5 client for a server on this Mac (127.0.0.1
/// only; nothing here ever reaches the network). Connect, then poll with
/// `outputStatus()`; any socket error drops the connection and fails every
/// pending request, and the caller reconnects.
public actor OBSClient {

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var nextRequestId = 0

    public init() {}

    public var isConnected: Bool { task != nil }

    /// Opens the socket and completes the Hello / Identify handshake.
    /// Throws `OBSProtocolError.authenticationFailed` when OBS refuses the
    /// password (or wants one and none was found).
    public func connect(port: Int, password: String?, timeout: Duration = .seconds(3)) async throws {
        disconnect()
        guard let url = URL(string: "ws://127.0.0.1:\(port)") else { throw OBSProtocolError.notConnected }

        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: url)
        task.resume()
        self.session = session

        var authRequired = false
        do {
            let hello = try OBSMessages.parseHello(try await Self.receiveData(task, timeout: timeout))
            authRequired = hello.requiresAuth
            try await task.send(.string(String(decoding: try OBSMessages.identify(hello: hello, password: password), as: UTF8.self)))
            let (op, _) = try OBSMessages.envelope(try await Self.receiveData(task, timeout: timeout))
            guard op == OBSOpCode.identified.rawValue else { throw OBSProtocolError.unexpectedOpCode(op) }
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            self.session = nil
            // OBS closes the socket (code 4009) right after a bad Identify; after
            // a Hello that asked for auth, any handshake failure means the password.
            if authRequired { throw OBSProtocolError.authenticationFailed }
            throw error
        }

        self.task = task
        receiveTask = Task { await self.receiveLoop(task) }
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        failAll(OBSProtocolError.notConnected)
    }

    /// Sends one request and returns its responseData as JSON.
    public func request(_ type: String, data: [String: Any]? = nil, timeout: Duration = .seconds(2)) async throws -> Data {
        guard let task else { throw OBSProtocolError.notConnected }
        nextRequestId += 1
        let id = "rs-\(nextRequestId)"
        let message = String(decoding: try OBSMessages.request(type: type, id: id, data: data), as: UTF8.self)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pending[id] = continuation
            Task {
                do {
                    try await task.send(.string(message))
                } catch {
                    await self.finish(id, with: .failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: timeout)
                await self.finish(id, with: .failure(OBSProtocolError.timedOut))
            }
        }
    }

    /// Current stream and record state in one call.
    public func outputStatus() async throws -> (stream: OBSOutputStatus, record: OBSOutputStatus) {
        let decoder = JSONDecoder()
        let stream = try decoder.decode(OBSOutputStatus.self, from: try await request("GetStreamStatus"))
        let record = try decoder.decode(OBSOutputStatus.self, from: try await request("GetRecordStatus"))
        return (stream, record)
    }

    // MARK: - Internals

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let data = try await Self.receiveData(socket, timeout: nil)
                let (op, payload) = try OBSMessages.envelope(data)
                if let response = OBSMessages.parseResponse(op: op, payload: payload) {
                    finish(response.requestId, with: response.result.mapError { $0 as Error })
                }
            } catch {
                // Socket gone (OBS quit, server turned off); only tear down if
                // this is still the live socket and not one already replaced.
                if socket === task { disconnect() }
                return
            }
        }
    }

    private func finish(_ id: String, with result: Result<Data, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
    }

    private func failAll(_ error: Error) {
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values { continuation.resume(throwing: error) }
    }

    private static func receiveData(_ socket: URLSessionWebSocketTask, timeout: Duration?) async throws -> Data {
        let message: URLSessionWebSocketTask.Message
        if let timeout {
            message = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
                group.addTask { try await socket.receive() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    socket.cancel(with: .goingAway, reason: nil)
                    throw OBSProtocolError.timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw OBSProtocolError.timedOut }
                return first
            }
        } else {
            message = try await socket.receive()
        }
        switch message {
        case .string(let text): return Data(text.utf8)
        case .data(let data):   return data
        @unknown default:       throw OBSProtocolError.malformedMessage
        }
    }
}
