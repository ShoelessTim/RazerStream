import Foundation

// Encodes and decodes RFC 6455 WebSocket frames as used by the Loupedeck/Razer
// serial protocol — binary frames only, no HTTP upgrade, no masking.

public enum WSFrameCodec {

    // MARK: - Encode

    /// Wraps protocol payload bytes in a WS binary frame for sending.
    ///
    /// The device requires client frames to have the MASK bit set but with an
    /// all-zero mask key (masking with zero is a no-op). This matches the
    /// "mutated websocket" framing used by the official software and
    /// foxxyz/loupedeck's serial connection.
    public static func encode(_ payload: Data) -> Data {
        var frame = Data()
        frame.append(WSOpcodes.binary)   // FIN=1, opcode=2

        let length = payload.count
        if length <= 125 {
            // [0x82, 0x80|len, mask key (4 zero bytes), payload]
            frame.append(0x80 | UInt8(length))
            frame.append(contentsOf: [0, 0, 0, 0])
        } else {
            // [0x82, 0xFF, 8-byte BE length, mask key (4 zero bytes), payload]
            frame.append(0xFF)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> shift) & 0xFF))
            }
            frame.append(contentsOf: [0, 0, 0, 0])
        }
        frame.append(payload)
        return frame
    }

    // MARK: - Decode

    public struct Frame {
        public let opcode: UInt8
        public let payload: Data
    }

    public enum DecodeError: Error {
        case incomplete(needed: Int)   // caller should buffer and retry with more data
        case unsupportedOpcode(UInt8)
        case masked                    // device should never send masked frames
    }

    /// Attempts to decode one WS frame from the head of `buffer`.
    /// On success returns the Frame and the number of bytes consumed.
    /// On `.incomplete`, the caller should buffer more data and try again.
    public static func decode(_ buffer: Data) -> Result<(Frame, consumed: Int), DecodeError> {
        guard buffer.count >= 2 else {
            return .failure(.incomplete(needed: 2 - buffer.count))
        }

        let firstByte  = buffer[buffer.startIndex]
        let secondByte = buffer[buffer.startIndex + 1]

        let opcode = firstByte & 0x0F
        let masked = (secondByte & 0x80) != 0
        guard !masked else { return .failure(.masked) }

        var headerLen = 2
        var payloadLen: Int

        let rawLen = Int(secondByte & 0x7F)
        if rawLen < 126 {
            payloadLen = rawLen
        } else if rawLen == 126 {
            guard buffer.count >= 4 else {
                return .failure(.incomplete(needed: 4 - buffer.count))
            }
            payloadLen = (Int(buffer[buffer.startIndex + 2]) << 8)
                       |  Int(buffer[buffer.startIndex + 3])
            headerLen = 4
        } else {
            guard buffer.count >= 10 else {
                return .failure(.incomplete(needed: 10 - buffer.count))
            }
            payloadLen = 0
            for i in 2..<10 {
                payloadLen = (payloadLen << 8) | Int(buffer[buffer.startIndex + i])
            }
            headerLen = 10
        }

        let totalLen = headerLen + payloadLen
        guard buffer.count >= totalLen else {
            return .failure(.incomplete(needed: totalLen - buffer.count))
        }

        let payloadStart = buffer.startIndex + headerLen
        let payload = buffer[payloadStart ..< payloadStart + payloadLen]
        return .success((Frame(opcode: opcode, payload: Data(payload)), totalLen))
    }
}

// MARK: - Stream reassembler

/// Accumulates raw serial bytes and emits complete WS frame payloads.
public final class WSFrameReassembler {
    private var buffer = Data()

    public init() {}

    /// Feed raw bytes from the serial port. Returns zero or more decoded payloads.
    public func feed(_ bytes: Data) -> [Data] {
        buffer.append(bytes)
        var results: [Data] = []

        while !buffer.isEmpty {
            switch WSFrameCodec.decode(buffer) {
            case .success(let (frame, consumed)):
                results.append(frame.payload)
                buffer = Data(buffer.dropFirst(consumed))
            case .failure(.incomplete):
                return results   // need more data from serial port
            case .failure(let err):
                print("[WSFrameReassembler] decode error: \(err), resyncing")
                buffer = Data(buffer.dropFirst(1))
            }
        }

        return results
    }
}
