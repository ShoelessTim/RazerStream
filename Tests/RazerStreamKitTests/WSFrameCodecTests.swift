import XCTest
@testable import RazerStreamKit

final class WSFrameCodecTests: XCTestCase {

    // MARK: - Encode (host → device: masked with zero key)

    func testEncodeSmallPayload() {
        let payload = Data([0x04, 0x09, 0x01, 0x00, 0x05]) // setBrightness=5
        let frame = WSFrameCodec.encode(payload)

        // [0x82, 0x80|length, mask key (4 zeros), ...payload]
        XCTAssertEqual(frame[0], 0x82)
        XCTAssertEqual(frame[1], 0x80 | UInt8(payload.count))
        XCTAssertEqual(Data(frame[2..<6]), Data([0, 0, 0, 0]))
        XCTAssertEqual(Data(frame[6...]), payload)
        XCTAssertEqual(frame.count, 6 + payload.count)
    }

    func testEncodeLargePayload() {
        // Payloads over 125 bytes use the 0xFF extended form:
        // [0x82, 0xFF, 8-byte BE length, mask key (4 zeros), payload]
        let payload = Data(repeating: 0xAB, count: 200)
        let frame = WSFrameCodec.encode(payload)

        XCTAssertEqual(frame[0], 0x82)
        XCTAssertEqual(frame[1], 0xFF)
        let length = frame[2..<10].reduce(0) { ($0 << 8) | Int($1) }
        XCTAssertEqual(length, 200)
        XCTAssertEqual(Data(frame[10..<14]), Data([0, 0, 0, 0]))
        XCTAssertEqual(Data(frame[14...]), payload)
    }

    // MARK: - Decode (device → host: standard unmasked frames)

    private func deviceFrame(_ payload: Data) -> Data {
        var frame = Data([0x82, UInt8(payload.count)])
        frame.append(payload)
        return frame
    }

    func testDecodeSmallFrame() {
        let payload = Data([0x05, 0x00, 0x00, 0x04, 0x00]) // button event
        let frame = deviceFrame(payload)

        let result = WSFrameCodec.decode(frame)
        guard case .success(let (decoded, consumed)) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(decoded.payload, payload)
        XCTAssertEqual(consumed, frame.count)
    }

    func testDecodeIncomplete() {
        let frame = Data([0x82, 0x05, 0x04]) // header says 5 bytes of payload, only 1 provided
        let result = WSFrameCodec.decode(frame)
        guard case .failure(.incomplete) = result else {
            return XCTFail("Expected .incomplete")
        }
    }

    func testDecodeRejectsMasked() {
        // Device should never send masked frames; decoder flags them
        let frame = Data([0x82, 0x85, 0, 0, 0, 0, 1, 2, 3, 4, 5])
        let result = WSFrameCodec.decode(frame)
        guard case .failure(.masked) = result else {
            return XCTFail("Expected .masked")
        }
    }

    // MARK: - Reassembler

    func testReassemblerSingleFrame() {
        let payload = Data([0x05, 0x00, 0x01, 0x04, 0x00])
        let frame = deviceFrame(payload)

        let reasm = WSFrameReassembler()
        let results = reasm.feed(frame)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], payload)
    }

    func testReassemblerChunkedDelivery() {
        let payload = Data([0x05, 0x00, 0x01, 0x04, 0x00])
        let frame = deviceFrame(payload)

        let reasm = WSFrameReassembler()
        let chunk1 = Data(frame.prefix(3))
        let chunk2 = Data(frame.suffix(from: 3))

        let r1 = reasm.feed(chunk1)
        XCTAssertTrue(r1.isEmpty, "Should be buffered, not emitted yet")

        let r2 = reasm.feed(chunk2)
        XCTAssertEqual(r2.count, 1)
        XCTAssertEqual(r2[0], payload)
    }

    func testReassemblerMultipleFrames() {
        let p1 = Data([0x05, 0x00, 0x01, 0x00, 0x00])
        let p2 = Data([0x05, 0x01, 0x02, 0x03, 0xFF])
        let combined = deviceFrame(p1) + deviceFrame(p2)

        let reasm = WSFrameReassembler()
        let results = reasm.feed(combined)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], p1)
        XCTAssertEqual(results[1], p2)
    }
}
