import Foundation
import RazerStreamKit
import AppKit

// Unbuffered output so events appear immediately even when piped to a file
setbuf(stdout, nil)

// MARK: - Entry point

let args = CommandLine.arguments.dropFirst()

if args.isEmpty {
    printHelp()
    exit(0)
}

switch args.first {
case "monitor":
    runMonitor()
case "list":
    runList()
case "brightness":
    runBrightness(args: Array(args.dropFirst()))
case "test-pattern":
    runTestPattern()
case "version":
    runVersion()
case "report":
    runReport()
case "help", "--help", "-h":
    printHelp()
default:
    print("Unknown command: \(args.first ?? "")")
    printHelp()
    exit(1)
}

// MARK: - Commands

func runMonitor() {
    print("Connecting to Razer Stream Controller...")
    do {
        let (device, events) = try RazerStreamDevice.connect()

        // Handle Ctrl-C cleanly
        let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sig.setEventHandler {
            print("\nDisconnecting...")
            device.close()
            exit(0)
        }
        signal(SIGINT, SIG_IGN)
        sig.resume()

        print("Listening for events (Ctrl-C to quit):\n")

        // Run the async event loop on a background Task, keep main thread alive
        let sema = DispatchSemaphore(value: 0)
        Task {
            for await event in events {
                print(event)
            }
            sema.signal()
        }
        sema.wait()

    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

/// What the device answered during the report's handshake. A small locked box
/// because the event stream is consumed on a Task while the report is printed
/// from the main thread.
private final class HandshakeAnswers: @unchecked Sendable {
    private let lock = NSLock()
    private var _firmware: String?
    private var _serialSeen = false

    var firmware: String? { lock.withLock { _firmware } }
    var serialSeen: Bool { lock.withLock { _serialSeen } }

    func setFirmware(_ v: String) { lock.withLock { _firmware = v } }
    func markSerialSeen() { lock.withLock { _serialSeen = true } }
}

/// Prints the hardware report people paste into a GitHub issue. The report
/// text itself is built in the kit so the app's "Copy Device Report" button
/// and this command produce identical output.
func runReport() {
    print("# Device report")
    print()
    print("Paste the block below into a GitHub issue:")
    print("https://github.com/ShoelessTim/RazerStream/issues/new?labels=device-report&template=device-report.md")
    print()

    // The app holds the serial port while it runs, so a handshake here would
    // block behind it; skip rather than hang. The USB identity, which is the
    // part that matters for adding a device, does not need the port at all.
    let appRunning = !NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == "org.community.razerstream"
    }.isEmpty

    var connection = DeviceReport.Connection.none
    if !appRunning, (try? SerialTransport.findDevice()) != nil {
        if let (device, events) = try? RazerStreamDevice.connect() {
            let answers = HandshakeAnswers()
            let done = DispatchSemaphore(value: 0)
            let task = Task {
                for await event in events {
                    switch event {
                    case .firmwareVersion(let v): answers.setFirmware(v); done.signal()
                    case .serialNumber: answers.markSerialSeen()
                    default: break
                    }
                }
            }
            _ = done.wait(timeout: .now() + 4)
            connection = .init(connected: true,
                               firmware: answers.firmware,
                               serialNumberSeen: answers.serialSeen)
            task.cancel()
            device.close()
        }
    }

    print("```")
    print(DeviceReport.generate(connection: connection), terminator: "")
    if appRunning {
        print()
        print("(RazerStream is running and holds the serial port, so the firmware")
        print(" line was skipped. Quit it and rerun for that detail.)")
    }
    print("```")
    print()
    print("Please also say which model it is, and whether the official software")
    print("still drives it on this Mac.")

    // The serial read runs on its own Thread, which would otherwise keep the
    // process alive after the report is printed.
    exit(0)
}

func runList() {
    print("Scanning for Razer Stream Controllers...")
    do {
        let paths = try SerialTransport.listDevices()
        if paths.isEmpty {
            print("No devices found. Check USB connection and permissions.")
        } else {
            print("Found \(paths.count) device(s):")
            for path in paths {
                print("  \(path)")
            }
        }
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

func runBrightness(args: [String]) {
    guard let first = args.first, let level = UInt8(first), level <= 10 else {
        print("Usage: rstream brightness <0-10>")
        exit(1)
    }

    do {
        let (device, events) = try RazerStreamDevice.connect()
        try device.send(.setBrightness(level))
        print("Brightness set to \(level)")

        // Give the command time to flush, then close
        Thread.sleep(forTimeInterval: 0.2)
        device.close()
        _ = events   // suppress unused warning
        exit(0)
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

func runTestPattern() {
    // Eight distinct colors, one per button zone, as RGB565
    let colors: [(name: String, r: UInt8, g: UInt8, b: UInt8)] = [
        ("red",     255, 0,   0),
        ("orange",  255, 140, 0),
        ("yellow",  255, 220, 0),
        ("green",   0,   200, 60),
        ("cyan",    0,   200, 220),
        ("blue",    30,  60,  255),
        ("purple",  160, 40,  220),
        ("white",   255, 255, 255),
    ]

    func rgb565(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (UInt8, UInt8) {
        let v: UInt16 = (UInt16(r & 0xF8) << 8) | (UInt16(g & 0xFC) << 3) | UInt16(b >> 3)
        return (UInt8(v & 0xFF), UInt8(v >> 8))   // little-endian
    }

    do {
        let (device, events) = try RazerStreamDevice.connect()
        _ = events

        // Wait for handshake to complete before drawing
        Thread.sleep(forTimeInterval: 2.0)

        // Restore brightness first — a previous session may have left it at 0
        try device.send(.setBrightness(10))
        Thread.sleep(forTimeInterval: 0.2)

        let px = RazerStreamController.buttonSize * RazerStreamController.buttonSize
        for (i, c) in colors.enumerated() {
            let (lo, hi) = rgb565(c.r, c.g, c.b)
            var buf = Data(capacity: px * 2)
            for _ in 0..<px { buf.append(lo); buf.append(hi) }
            try device.send(.setButtonImage(button: i, rgb565: buf))
            print("Button \(i): \(c.name)")
            Thread.sleep(forTimeInterval: 0.1)
        }

        print("Test pattern sent — holding session open for 60s so it stays visible.")
        Thread.sleep(forTimeInterval: 60)
        device.close()
        exit(0)
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

func runVersion() {
    do {
        let (device, events) = try RazerStreamDevice.connect()
        let sema = DispatchSemaphore(value: 0)
        Task {
            for await event in events {
                switch event {
                case .firmwareVersion, .serialNumber:
                    print(event)
                case .error:
                    print(event)
                    sema.signal()
                    return
                default:
                    break
                }
                // Exit after we have both version and serial
                if case .serialNumber = event { sema.signal() }
            }
        }
        // Timeout after 3s in case device doesn't respond
        if sema.wait(timeout: .now() + 3) == .timedOut {
            print("Timed out waiting for version info.")
        }
        device.close()
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

// MARK: - Help

func printHelp() {
    print("""
    rstream — Razer Stream Controller CLI

    Usage:
      rstream list                List connected devices
      rstream monitor             Print all device events (buttons, knobs, touch)
      rstream brightness <0-10>   Set display brightness
      rstream version             Print firmware version and serial number

    Examples:
      rstream monitor
      rstream brightness 7
    """)
}
