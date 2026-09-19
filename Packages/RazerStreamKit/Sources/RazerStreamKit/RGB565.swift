import Foundation

public enum RGB565 {
    /// Rotates a top-row-first, little-endian RGB565 buffer 90 degrees
    /// counterclockwise. The returned dimensions are height by width.
    public static func rotatedCounterClockwise(
        _ data: Data,
        width: Int,
        height: Int
    ) -> Data? {
        guard width > 0, height > 0, data.count == width * height * 2 else {
            return nil
        }

        let outputWidth = height
        var output = Data(count: data.count)
        output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { inputBytes in
                guard let source = inputBytes.bindMemory(to: UInt8.self).baseAddress,
                      let destination = outputBytes.bindMemory(to: UInt8.self).baseAddress
                else { return }

                for y in 0..<height {
                    for x in 0..<width {
                        let outputX = y
                        let outputY = width - 1 - x
                        let sourceOffset = (y * width + x) * 2
                        let destinationOffset = (outputY * outputWidth + outputX) * 2
                        destination[destinationOffset] = source[sourceOffset]
                        destination[destinationOffset + 1] = source[sourceOffset + 1]
                    }
                }
            }
        }
        return output
    }
}
