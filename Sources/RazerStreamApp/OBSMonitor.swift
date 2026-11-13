import Foundation
import OBSKit

// Keeps a live picture of OBS on this Mac: connects with the password OBS
// itself saved (never typed into or stored by RazerStream), polls stream and
// record state once a second, and reconnects on its own when OBS restarts.
// Built for a Mac with no screen in use: the deck is the only feedback, so
// every state, including "OBS is not running", ends up on a light.

@MainActor
final class OBSMonitor: ObservableObject {

    @Published private(set) var snapshot = OBSSnapshot()

    private let client = OBSClient()
    private var loop: Task<Void, Never>?

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

    /// One connection's lifetime: returns when the connection is lost or fails.
    private func connectAndPoll() async {
        let config = OBSConfigReader.load() ?? .default
        guard config.enabled else {
            snapshot = OBSSnapshot(connection: .notRunning)
            return
        }

        do {
            try await client.connect(port: config.port, password: config.password)
        } catch OBSProtocolError.authenticationFailed {
            snapshot = OBSSnapshot(connection: .authFailed)
            return
        } catch {
            snapshot = OBSSnapshot(connection: .notRunning)
            return
        }

        snapshot.connection = .connected
        while !Task.isCancelled {
            do {
                let status = try await client.outputStatus()
                snapshot = OBSSnapshot(connection: .connected, stream: status.stream,
                                       record: status.record, lastUpdate: Date())
            } catch {
                await client.disconnect()
                snapshot.connection = .notRunning
                return
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }
}
