import Foundation
import OBSKit

// Keeps a live picture of OBS on this Mac: connects with the password OBS
// itself saved (never typed into or stored by RazerStream), polls once a
// second, and reconnects on its own when OBS restarts. Also sends the deck's
// OBS commands (go live, record, scenes, mic, volume).
// Built for a Mac with no screen in use: the deck is the only feedback, so
// every state, including "OBS is not running", ends up on a light or tile.

@MainActor
final class OBSMonitor: ObservableObject {

    @Published private(set) var snapshot = OBSSnapshot()

    /// Called on the main actor with each alert the deck should buzz for.
    var onAlert: ((OBSAlert) -> Void)?

    private let client = OBSClient()
    private var loop: Task<Void, Never>?
    private var alerts = OBSAlertTracker()
    private var lastBytes: (bytes: Double, at: Date)?

    private static let pollInterval: Duration = .seconds(1)
    private static let retryInterval: Duration = .seconds(3)

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.connectAndPoll()
                try? await Task.sleep(for: Self.retryInterval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        let client = client
        Task { await client.disconnect() }
        snapshot = OBSSnapshot()
    }

    // MARK: - Commands (fire and forget; the next poll shows the result)

    func toggleStream() {
        if snapshot.isLive { alerts.noteUserEndedStream(at: Date()) }
        send { try await $0.toggleStream() }
    }

    func toggleRecord() { send { try await $0.toggleRecord() } }

    func selectScene(slot: Int) {
        guard snapshot.scenes.indices.contains(slot) else { return }
        let name = snapshot.scenes[slot]
        snapshot.currentScene = name   // show it right away; the poll confirms
        send { try await $0.setScene(name) }
    }

    func toggleMute(_ target: OBSAudioTarget) {
        guard let input = inputName(target) else { return }
        if target == .mic, let muted = snapshot.micMuted { snapshot.micMuted = !muted }
        send { try await $0.toggleInputMute(input) }
    }

    func nudgeVolume(_ target: OBSAudioTarget, steps: Int) {
        guard let input = inputName(target) else { return }
        send { try await $0.adjustInputVolume(input, deltaDb: Double(steps)) }
    }

    private func inputName(_ target: OBSAudioTarget) -> String? {
        switch target {
        case .mic:     return snapshot.micInput
        case .desktop: return snapshot.desktopInput
        }
    }

    private func send(_ command: @escaping @Sendable (OBSClient) async throws -> Void) {
        let client = client
        Task { try? await command(client) }
    }

    // MARK: - Connection and polling

    /// One connection's lifetime: returns when the connection is lost or fails.
    private func connectAndPoll() async {
        let config = OBSConfigReader.load() ?? .default
        guard config.enabled else {
            publish(OBSSnapshot(connection: .notRunning))
            return
        }

        do {
            try await client.connect(port: config.port, password: config.password)
        } catch OBSProtocolError.authenticationFailed {
            publish(OBSSnapshot(connection: .authFailed))
            return
        } catch {
            publish(OBSSnapshot(connection: .notRunning))
            return
        }

        let inputs = try? await client.specialInputs()
        lastBytes = nil

        while !Task.isCancelled {
            do {
                let status = try await client.outputStatus()
                let stats = try? await client.stats()
                let scenes = try? await client.sceneList()
                var micMuted: Bool?
                if let mic = inputs?.mic { micMuted = try? await client.inputMuted(mic) }

                let now = Date()
                var next = OBSSnapshot(connection: .connected, stream: status.stream,
                                       record: status.record, lastUpdate: now)
                next.scenes = scenes?.namesTopFirst ?? []
                next.currentScene = scenes?.currentProgramSceneName
                next.micInput = inputs?.mic
                next.desktopInput = inputs?.desktop
                next.micMuted = micMuted
                next.cpuUsage = stats?.cpuUsage
                next.activeFps = stats?.activeFps
                next.bitrateKbps = bitrate(status.stream, at: now)
                publish(next)
            } catch {
                await client.disconnect()
                var lost = snapshot
                lost.connection = .notRunning
                publish(lost)
                return
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func bitrate(_ stream: OBSOutputStatus, at now: Date) -> Double? {
        guard stream.outputActive, let bytes = stream.outputBytes else {
            lastBytes = nil
            return nil
        }
        defer { lastBytes = (bytes, now) }
        guard let last = lastBytes else { return nil }
        return OBSRates.kbps(fromBytes: last.bytes, at: last.at, toBytes: bytes, at: now)
            ?? snapshot.bitrateKbps
    }

    private func publish(_ next: OBSSnapshot) {
        snapshot = next
        for alert in alerts.update(next, at: Date()) { onAlert?(alert) }
    }
}

/// Which OBS audio input a knob drives.
enum OBSAudioTarget: String, Codable, CaseIterable, Hashable {
    case mic
    case desktop

    var label: String { self == .mic ? "MIC" : "DESK" }
}
