import Foundation

// Builds the hardware report people paste into a GitHub issue when their deck
// is not supported yet.
//
// Lives in the kit so the app and the CLI produce identical text. The app
// passes the firmware it already knows from its live connection; the CLI does
// its own handshake first and passes the result.
//
// Deliberately hardware facts only: USB ids, product strings, macOS version.
// No profile contents, no file paths, no serial number value, nothing tied to
// the person running it, so it is safe to paste in public without an audit.

public enum DeviceReport {

    /// What the caller already knows about a live connection, if anything.
    public struct Connection: Sendable {
        public let connected: Bool
        public let firmware: String?
        public let serialNumberSeen: Bool

        public init(connected: Bool, firmware: String? = nil, serialNumberSeen: Bool = false) {
            self.connected = connected
            self.firmware = firmware
            self.serialNumberSeen = serialNumberSeen
        }

        public static let none = Connection(connected: false)
    }

    /// The pasteable block, without surrounding prose or fences.
    public static func generate(connection: Connection = .none) -> String {
        var out = "RazerStream device report\n"
        out += "App version: \(appVersion)\n"
        out += "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        out += "Architecture: \(architecture)\n\n"

        let devices = SerialTransport.enumerateSerialDevices()
        if devices.isEmpty {
            out += "No USB serial devices found at all.\n"
            out += "If the deck is plugged in it may not present a serial interface,\n"
            out += "which is itself worth knowing; please say which model it is.\n"
        } else {
            out += "USB serial devices seen (\(devices.count)):\n"
            for d in devices {
                out += "  \(d.path)\n"
                out += "    \(d.idString)\(d.isKnown ? "  [supported]" : "")\n"
                if let p = d.product { out += "    product: \(p)\n" }
                if let m = d.manufacturer { out += "    manufacturer: \(m)\n" }
            }
        }
        out += "\n"

        if connection.connected {
            out += "Connection: yes\n"
            out += "  firmware: \(connection.firmware ?? "(not reported)")\n"
            out += "  serial number reported: \(connection.serialNumberSeen ? "yes" : "no")  (value withheld)\n"
        } else if devices.contains(where: { $0.isKnown }) {
            out += "Connection: a supported device is attached but not currently connected.\n"
        } else {
            out += "Connection: no supported device attached.\n"
            out += "If one of the devices above is a Loupedeck or Razer deck, that\n"
            out += "VID/PID pair is what is needed to start adding it.\n"
        }
        return out
    }

    private static var architecture: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "(source build)"
    }
}
