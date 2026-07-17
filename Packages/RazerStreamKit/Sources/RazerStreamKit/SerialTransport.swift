import Foundation
import IOKit
import IOKit.usb
import IOKit.serial

// Finds the Razer Stream Controller by VID/PID and opens a serial connection
// using IOKit + POSIX termios + DispatchIO.

public final class SerialTransport {

    // MARK: - Public

    public let devicePath: String

    public init(devicePath: String) {
        self.devicePath = devicePath
    }

    // MARK: - Device Discovery

    /// Returns the /dev/cu.* path for the first matching Razer Stream Controller.
    public static func findDevice(
        vendorID: UInt16 = RazerStreamController.vendorID,
        productID: UInt16 = RazerStreamController.productID
    ) throws -> String {
        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue)
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS else {
            throw TransportError.iokit("IOServiceGetMatchingServices failed: \(result)")
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }

            // Walk up the parent tree to find the USB device with our VID/PID
            guard matchesVIDPID(service: service, vendorID: vendorID, productID: productID) else {
                continue
            }

            // Get the BSD path (e.g. /dev/cu.usbmodem14401)
            if let path = serialBSDPath(for: service) {
                return path
            }
        }

        throw TransportError.deviceNotFound(
            "No Razer Stream Controller found (VID=0x\(String(vendorID, radix: 16)) PID=0x\(String(productID, radix: 16)))"
        )
    }

    /// Returns all connected /dev/cu.* paths that match any Razer Stream Controller PID.
    public static func listDevices() throws -> [String] {
        var paths: [String] = []
        let pids: [UInt16] = [RazerStreamController.productID, RazerStreamController.productIDX]

        for pid in pids {
            if let path = try? findDevice(vendorID: RazerStreamController.vendorID, productID: pid) {
                paths.append(path)
            }
        }
        return paths
    }

    // MARK: - Open / Close

    // Separate descriptors for read and write, mirroring the proven-working
    // shell pattern (`cat port &` + `printf > port`). A single O_RDWR fd
    // never receives data from this device's CDC interface.
    private var readFD: Int32 = -1
    private var writeFD: Int32 = -1
    private var readThread: Thread?
    private var keepReading = false

    /// Opens the serial port (separate read and write descriptors) and
    /// configures termios.
    public func open() throws {
        // Configure termios via a throwaway fd first, exactly like `stty -f`
        let cfgFD = Darwin.open(devicePath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard cfgFD >= 0 else {
            throw TransportError.openFailed(devicePath, errno)
        }
        do {
            try configureTermios(fd: cfgFD)
        } catch {
            Darwin.close(cfgFD)
            throw error
        }
        // Assert DTR + RTS so the device knows a host is listening
        var modemBits: Int32 = TIOCM_DTR | TIOCM_RTS
        _ = ioctl(cfgFD, TIOCMBIS, &modemBits)
        Darwin.close(cfgFD)

        readFD = Darwin.open(devicePath, O_RDONLY | O_NOCTTY)
        guard readFD >= 0 else {
            throw TransportError.openFailed(devicePath, errno)
        }

        writeFD = Darwin.open(devicePath, O_WRONLY | O_NOCTTY)
        guard writeFD >= 0 else {
            Darwin.close(readFD)
            readFD = -1
            throw TransportError.openFailed(devicePath, errno)
        }
    }

    public func close() {
        keepReading = false
        if readFD >= 0 {
            Darwin.close(readFD)   // unblocks any pending read()
            readFD = -1
        }
        if writeFD >= 0 {
            Darwin.close(writeFD)
            writeFD = -1
        }
    }

    // MARK: - Async Read

    /// Starts a background thread that blocks on read() and calls `handler`
    /// for each chunk of bytes. `onDisconnect` fires once if the port dies
    /// (USB unplugged, read error, or a run of EOFs). Call after `open()`.
    public func startReading(
        handler: @escaping (Data) -> Void,
        onDisconnect: @escaping () -> Void = {}
    ) throws {
        guard readFD >= 0 else { throw TransportError.notOpen }

        let debug = ProcessInfo.processInfo.environment["RSTREAM_DEBUG"] != nil
        keepReading = true
        let thread = Thread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            if debug { print("[read-thread] started, fd=\(self?.readFD ?? -99)") }
            var zeroReads = 0
            var disconnected = false
            while let self = self, self.keepReading, self.readFD >= 0 {
                let n = Darwin.read(self.readFD, &buf, buf.count)
                if n > 0 {
                    if debug { print("[read-thread] got \(n) bytes") }
                    zeroReads = 0
                    handler(Data(buf[0..<n]))
                } else if n == 0 {
                    // With VMIN=1 a live port blocks; a flood of instant EOFs
                    // means the device was pulled. Treat a sustained run as a
                    // disconnect rather than spinning forever.
                    zeroReads += 1
                    if zeroReads >= 200 {
                        disconnected = true
                        break
                    }
                    usleep(5000)      // 5ms; avoid a busy spin on a dead port
                } else {
                    if errno == EINTR { continue }
                    // Any real read error on a serial port means it's gone
                    if self.keepReading {
                        if debug { print("[read-thread] read failed: errno \(errno) (\(String(cString: strerror(errno))))") }
                        disconnected = true
                    }
                    break
                }
            }
            if debug { print("[read-thread] exiting (disconnected=\(disconnected))") }
            // Only signal if we weren't asked to stop (close() sets keepReading=false)
            if disconnected, let self, self.keepReading {
                onDisconnect()
            }
        }
        thread.name = "com.razerstream.serial-read"
        thread.qualityOfService = .userInteractive
        thread.start()
        readThread = thread
    }

    // MARK: - Write

    public func write(_ data: Data) throws {
        guard writeFD >= 0 else { throw TransportError.notOpen }
        let written = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return 0 }
            return Darwin.write(writeFD, base, data.count)
        }
        if written < 0 {
            throw TransportError.writeFailed(errno)
        }
    }

    // MARK: - Termios configuration

    private func configureTermios(fd: Int32) throws {
        var tios = termios()
        guard tcgetattr(fd, &tios) == 0 else {
            throw TransportError.termiosFailed("tcgetattr", errno)
        }

        cfmakeraw(&tios)

        // 9600 8N1, no flow control — mirrors the config `stty raw` produces,
        // which is confirmed working with this device. Notably: ONE stop bit
        // (CSTOPB off) and carrier handling left on (CLOCAL off, HUPCL on);
        // the device's CDC firmware ignores frames sent with other settings.
        cfsetispeed(&tios, speed_t(B9600))
        cfsetospeed(&tios, speed_t(B9600))

        tios.c_cflag &= ~UInt(PARENB)               // no parity
        tios.c_cflag &= ~UInt(CSTOPB)               // 1 stop bit
        tios.c_cflag &= ~UInt(CSIZE)
        tios.c_cflag |= UInt(CS8)                   // 8 data bits
        tios.c_cflag &= ~UInt(CRTSCTS)              // no hardware flow control
        tios.c_cflag &= ~UInt(CLOCAL)
        tios.c_cflag |= UInt(CREAD | HUPCL)

        // VMIN=1: block until at least one byte arrives. VMIN=0 would make
        // read() return 0 on an idle port, which DispatchIO treats as EOF
        // and permanently stops the read stream.
        withUnsafeMutableBytes(of: &tios.c_cc) { ptr in
            ptr[Int(VMIN)]  = 1
            ptr[Int(VTIME)] = 0
        }

        guard tcsetattr(fd, TCSANOW, &tios) == 0 else {
            throw TransportError.termiosFailed("tcsetattr", errno)
        }
    }

    // MARK: - IOKit helpers

    private static func matchesVIDPID(service: io_object_t, vendorID: UInt16, productID: UInt16) -> Bool {
        var parent: io_object_t = IO_OBJECT_NULL
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        // Walk up the IORegistry tree to find the USB device node
        while true {
            let vid = ioRegistryInteger(service: current, key: "idVendor")
            let pid = ioRegistryInteger(service: current, key: "idProduct")
            if let vid = vid, let pid = pid {
                return UInt16(vid) == vendorID && UInt16(pid) == productID
            }
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS,
                  parent != IO_OBJECT_NULL else {
                break
            }
            IOObjectRelease(current)
            current = parent
        }
        return false
    }

    private static func serialBSDPath(for service: io_object_t) -> String? {
        let key = kIOCalloutDeviceKey as CFString
        guard let cfValue = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String else {
            return nil
        }
        return cfValue
    }

    private static func ioRegistryInteger(service: io_object_t, key: String) -> Int? {
        guard let cfValue = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() else { return nil }
        return (cfValue as? Int) ?? (cfValue as? NSNumber).map { $0.intValue }
    }
}

// MARK: - Errors

public enum TransportError: Error, CustomStringConvertible {
    case deviceNotFound(String)
    case openFailed(String, Int32)
    case termiosFailed(String, Int32)
    case notOpen
    case writeFailed(Int32)
    case iokit(String)

    public var description: String {
        switch self {
        case .deviceNotFound(let msg):  return "Device not found: \(msg)"
        case .openFailed(let p, let e): return "Failed to open \(p): errno \(e)"
        case .termiosFailed(let fn, let e): return "\(fn) failed: errno \(e)"
        case .notOpen:                  return "Serial port not open"
        case .writeFailed(let e):       return "Write failed: errno \(e)"
        case .iokit(let msg):           return "IOKit error: \(msg)"
        }
    }
}
