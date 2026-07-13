import XCTest
@testable import RazerStreamKit

final class DeviceCommandTests: XCTestCase {

    func testSetBrightnessEncoding() {
        let (cmd, payload) = DeviceCommand.setBrightness(7).encode()
        XCTAssertEqual(cmd, .setBrightness)
        XCTAssertEqual(payload, Data([0x00, 0x07]))
    }

    func testSetBrightnessClamped() {
        let (_, payload) = DeviceCommand.setBrightness(99).encode()
        XCTAssertEqual(payload[1], maxBrightness, "Should clamp to maxBrightness")
    }

    func testSetButtonColor() {
        let (cmd, payload) = DeviceCommand.setButtonColor(button: 3, r: 255, g: 128, b: 0).encode()
        XCTAssertEqual(cmd, .setColor)
        XCTAssertEqual(payload, Data([0x03, 255, 128, 0]))
    }

    func testButtonImageOffset() {
        // Button 4 is row=1, col=0 → x=60 (center offset), y=90
        let (cmd, payload) = DeviceCommand.setButtonImage(button: 4, rgb565: Data()).encode()
        XCTAssertEqual(cmd, .frameBuffer)
        // payload[0..1] = display ID "\0M", then x(2), y(2), w(2), h(2)
        XCTAssertEqual(payload[0], 0x00)
        XCTAssertEqual(payload[1], 0x4D)
        let x = Int(payload[2]) << 8 | Int(payload[3])
        let y = Int(payload[4]) << 8 | Int(payload[5])
        XCTAssertEqual(x, 60)
        XCTAssertEqual(y, 90)
    }

    func testVibrateEncoding() {
        let (cmd, payload) = DeviceCommand.vibrate(.short).encode()
        XCTAssertEqual(cmd, .setVibration)
        XCTAssertEqual(payload, Data([Haptic.short.rawValue]))
    }

    func testRequestVersion() {
        let (cmd, payload) = DeviceCommand.requestVersion.encode()
        XCTAssertEqual(cmd, .version)
        XCTAssertTrue(payload.isEmpty)
    }

    func testReset() {
        let (cmd, _) = DeviceCommand.reset.encode()
        XCTAssertEqual(cmd, .reset)
    }
}
