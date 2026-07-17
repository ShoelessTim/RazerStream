import Foundation

// High-level device interface. Connects via SerialTransport, speaks the
// Loupedeck/Razer WebSocket-over-serial protocol, and vends an AsyncStream
// of DeviceEvents. All public methods are safe to call from any actor.

public final class RazerStreamDevice: @unchecked Sendable {

    // MARK: - Public properties

    public let transport: SerialTransport

    // MARK: - Private state

    private let reassembler = WSFrameReassembler()
    private var txID: UInt8 = 1

    private var continuation: AsyncStream<DeviceEvent>.Continuation?
    private let lock = NSLock()

    // The device requires an HTTP-style websocket upgrade over serial before
    // it will speak WS frames. Until the response arrives, buffer raw bytes.
    private var handshakeComplete = false
    private var handshakeBuffer = Data()

    // NOTE: must end with a blank line ("\n\n") — that's how HTTP marks the
    // end of headers. Without it the device waits forever and never replies.
    private static let handshakeRequest = Data(
        "GET /index.html\nHTTP/1.1\nConnection: Upgrade\nUpgrade: websocket\nSec-WebSocket-Key: 123abc\n\n".utf8
    )

    // MARK: - Init

    public init(transport: SerialTransport) {
        self.transport = transport
    }

    /// Convenience: auto-discover and connect.
    public static func connect() throws -> (RazerStreamDevice, AsyncStream<DeviceEvent>) {
        let path = try SerialTransport.findDevice()
        let transport = SerialTransport(devicePath: path)
        let device = RazerStreamDevice(transport: transport)
        let stream = try device.open()
        return (device, stream)
    }

    // MARK: - Open / Close

    /// Opens the serial port and returns an AsyncStream of device events.
    public func open() throws -> AsyncStream<DeviceEvent> {
        let stream = AsyncStream<DeviceEvent> { [weak self] continuation in
            self?.lock.withLock { self?.continuation = continuation }
        }

        try transport.open()

        try transport.startReading(
            handler: { [weak self] data in
                self?.receive(data)
            },
            onDisconnect: { [weak self] in
                self?.emit(.disconnected(reason: "device unplugged"))
                self?.close()
            }
        )

        // Kick off the websocket upgrade; version/serial are requested once
        // the device acknowledges the handshake (see receive()).
        try transport.write(Self.handshakeRequest)

        // The device only answers the upgrade once per power-cycle. If it was
        // already switched into WS mode by a previous session, no response
        // comes — fall back to assuming WS mode after a short wait.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.lock.withLock({ self.handshakeComplete }) else { return }
            self.lock.withLock {
                self.handshakeComplete = true
                self.handshakeBuffer = Data()
            }
            self.emit(.connected)
            try? self.send(.requestVersion)
            try? self.send(.requestSerial)
        }

        return stream
    }

    public func close() {
        transport.close()
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }

    // MARK: - Send commands

    public func send(_ command: DeviceCommand) throws {
        let (cmd, payload) = command.encode()
        let id = nextTxID()

        var message = Data(capacity: 3 + payload.count)
        // Protocol message: [msgLength(1), command(1), txID(1), ...payload]
        let msgLength = UInt8(min(3 + payload.count, Int(UInt8.max)))
        message.append(msgLength)
        message.append(cmd.rawValue)
        message.append(id)
        message.append(payload)

        let frame = WSFrameCodec.encode(message)
        try transport.write(frame)

        if Self.debug {
            let hex = frame.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
            print("[TX \(frame.count)B] \(hex)\(frame.count > 32 ? " …" : "")")
        }

        // FRAMEBUFF always needs a DRAW command to push pixels to screen
        if case .frameBuffer = cmd {
            try sendDraw()
        }
    }

    // MARK: - Receive & parse

    private static let debug = ProcessInfo.processInfo.environment["RSTREAM_DEBUG"] != nil

    private func receive(_ data: Data) {
        var data = data
        if Self.debug {
            let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
            print("[RX \(data.count)B] \(hex)")
        }

        if !lock.withLock({ handshakeComplete }) {
            handshakeBuffer.append(data)
            // Wait for the COMPLETE header block — "HTTP/1.1" alone means
            // headers are still streaming in and must not hit the WS parser.
            guard let terminator = handshakeBuffer.range(of: Data("\r\n\r\n".utf8)),
                  let response = String(data: handshakeBuffer[..<terminator.lowerBound], encoding: .ascii),
                  response.contains("HTTP/1.1") else {
                return   // still waiting for the upgrade response
            }
            lock.withLock { handshakeComplete = true }
            emit(.connected)

            // Any bytes after the header terminator are already WS frames
            data = Data(handshakeBuffer[terminator.upperBound...])
            handshakeBuffer = Data()

            try? send(.requestVersion)
            try? send(.requestSerial)

            if data.isEmpty { return }
        }

        let payloads = reassembler.feed(data)
        for payload in payloads {
            parse(payload)
        }
    }

    private func parse(_ data: Data) {
        guard data.count >= 3 else { return }
        let msgLength = Int(data[0])
        guard let cmd = Command(rawValue: data[1]) else {
            // Unknown command, ignore
            return
        }
        // data[2] is txID (for response matching — not yet used)
        let body = data.count > 3 ? Data(data[3..<min(msgLength, data.count)]) : Data()

        switch cmd {
        case .buttonPress:
            parseButton(body)
        case .knobRotate:
            parseKnob(body)
        case .touch, .touchCT:
            parseTouch(body, ended: false)
        case .touchEnd, .touchEndCT:
            parseTouch(body, ended: true)
        case .version:
            parseVersion(body)
        case .serial:
            parseSerial(body)
        default:
            break
        }
    }

    private func parseButton(_ body: Data) {
        guard body.count >= 2 else { return }
        let buttonID = Int(body[0])
        let pressed = body[1] == 0x00
        emit(.buttonPress(id: buttonID, pressed: pressed))
    }

    private func parseKnob(_ body: Data) {
        guard body.count >= 2 else { return }
        let knobID = Int(body[0])
        let delta = Int(Int8(bitPattern: body[1]))
        emit(.knobRotate(id: knobID, delta: delta))
    }

    private func parseTouch(_ body: Data, ended: Bool) {
        // Touch payload: [?, x_hi, x_lo, y_hi, y_lo, touchID]
        guard body.count >= 6 else { return }
        let x = Int(body[1]) << 8 | Int(body[2])
        let y = Int(body[3]) << 8 | Int(body[4])
        let touchID = Int(body[5])
        if ended {
            emit(.touchEnd(x: x, y: y, touchID: touchID))
        } else {
            emit(.touchStart(x: x, y: y, touchID: touchID))
        }
    }

    private func parseVersion(_ body: Data) {
        guard body.count >= 3 else { return }
        let v = "\(body[0]).\(body[1]).\(body[2])"
        emit(.firmwareVersion(v))
    }

    private func parseSerial(_ body: Data) {
        if let s = String(data: body.filter { $0 != 0 }, encoding: .utf8) {
            emit(.serialNumber(s))
        }
    }

    // MARK: - Helpers

    private func sendDraw() throws {
        let id = nextTxID()
        // DRAW takes the 2-byte display ID as payload to refresh the screen
        let message = Data([0x05, Command.draw.rawValue, id] + RazerStreamController.displayID)
        let frame = WSFrameCodec.encode(message)
        try transport.write(frame)
    }

    private func emit(_ event: DeviceEvent) {
        _ = lock.withLock { continuation?.yield(event) }
    }

    private func nextTxID() -> UInt8 {
        lock.withLock {
            let id = txID
            txID = txID == 255 ? 1 : txID + 1
            return id
        }
    }
}
