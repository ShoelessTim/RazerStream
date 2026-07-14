import Foundation
import RazerStreamKit

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
