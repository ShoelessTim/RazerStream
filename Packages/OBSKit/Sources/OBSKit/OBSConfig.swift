import Foundation

/// Where and how to reach the local OBS WebSocket server.
public struct OBSServerConfig: Equatable, Sendable {
    public var enabled: Bool
    public var port: Int
    public var password: String?   // nil when authentication is off

    public init(enabled: Bool = true, port: Int = 4455, password: String? = nil) {
        self.enabled = enabled
        self.port = port
        self.password = password
    }

    public static let `default` = OBSServerConfig()
}

/// Reads the WebSocket server settings OBS itself saved on this Mac, so the
/// user never has to type the password into RazerStream. Nothing is copied
/// or stored elsewhere; the file is read fresh on every connect attempt, so
/// a password changed in OBS is picked up automatically.
///
/// Two layouts exist in the wild, newest first:
///   plugin_config/obs-websocket/config.json  (server_enabled, server_port,
///                                              auth_required, server_password)
///   user.ini or global.ini, [OBSWebSocket]   (ServerEnabled, ServerPort,
///                                              AuthRequired, ServerPassword)
public enum OBSConfigReader {

    public static var defaultOBSDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/obs-studio", isDirectory: true)
    }

    /// Best available config, or nil if OBS has never saved any.
    public static func load(obsDirectory: URL = defaultOBSDirectory) -> OBSServerConfig? {
        let json = obsDirectory.appendingPathComponent("plugin_config/obs-websocket/config.json")
        if let data = try? Data(contentsOf: json), let config = parseJSON(data) {
            return config
        }
        for name in ["user.ini", "global.ini"] {
            let url = obsDirectory.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8), let config = parseINI(text) {
                return config
            }
        }
        return nil
    }

    public static func parseJSON(_ data: Data) -> OBSServerConfig? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // A file without any server key is not this config; do not invent defaults from it.
        let keys = ["server_enabled", "server_port", "auth_required", "server_password"]
        guard keys.contains(where: { object[$0] != nil }) else { return nil }

        let enabled = object["server_enabled"] as? Bool ?? true
        let port = (object["server_port"] as? NSNumber)?.intValue ?? 4455
        let authRequired = object["auth_required"] as? Bool ?? true
        let password = object["server_password"] as? String
        return OBSServerConfig(
            enabled: enabled,
            port: port,
            password: authRequired ? nonEmpty(password) : nil
        )
    }

    public static func parseINI(_ text: String) -> OBSServerConfig? {
        var inSection = false
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = line == "[OBSWebSocket]"
                continue
            }
            guard inSection, let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        guard !values.isEmpty else { return nil }

        let enabled = values["ServerEnabled"].map(iniBool) ?? true
        let port = values["ServerPort"].flatMap(Int.init) ?? 4455
        let authRequired = values["AuthRequired"].map(iniBool) ?? true
        return OBSServerConfig(
            enabled: enabled,
            port: port,
            password: authRequired ? nonEmpty(values["ServerPassword"]) : nil
        )
    }

    private static func iniBool(_ value: String) -> Bool {
        ["true", "1", "yes"].contains(value.lowercased())
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
