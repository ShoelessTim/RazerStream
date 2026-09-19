import XCTest
@testable import RazerStreamKit

final class RGB565Tests: XCTestCase {
    func testCounterClockwiseRotation() throws {
        let input = pixels([1, 2, 3,
                            4, 5, 6])

        let output = try XCTUnwrap(RGB565.rotatedCounterClockwise(
            input, width: 3, height: 2
        ))

        XCTAssertEqual(values(output), [3, 6,
                                        2, 5,
                                        1, 4])
    }

    func testRotationRejectsWrongBufferSize() {
        XCTAssertNil(RGB565.rotatedCounterClockwise(Data([0, 1]), width: 2, height: 2))
    }

    private func pixels(_ values: [UInt16]) -> Data {
        var data = Data(capacity: values.count * 2)
        for value in values {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8(value >> 8))
        }
        return data
    }

    private func values(_ data: Data) -> [UInt16] {
        stride(from: 0, to: data.count, by: 2).map { offset in
            UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        }
    }
}
