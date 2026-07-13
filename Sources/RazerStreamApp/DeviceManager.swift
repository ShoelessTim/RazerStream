import Foundation
import RazerStreamKit

// Owns the device connection for the app's lifetime: connects, auto-reconnects,
// pushes tile images, and routes incoming events to the ActionEngine.

@MainActor
final class DeviceManager: ObservableObject {

    @Published var connected = false
    @Published var firmware: String = "—"
    @Published var serial: String = "—"
    @Published var lastEvent: String = "—"

    private var device: RazerStreamDevice?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    weak var store: ProfileStore?

    func start(store: ProfileStore) {
        self.store = store
        connectLoop()
    }

    func stop() {
        eventTask?.cancel()
        reconnectTask?.cancel()
        device?.close()
        device = nil
        connected = false
    }

    // MARK: - Connection

    private func connectLoop() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.device == nil {
                    do {
                        let (dev, events) = try RazerStreamDevice.connect()
                        self.device = dev
                        self.pump(events)
                    } catch {
                        // Device not present yet — retry quietly
                    }
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func pump(_ events: AsyncStream<DeviceEvent>) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
            // Stream ended → disconnected
            self?.connected = false
            self?.device = nil
        }
    }

    // MARK: - Event routing

    private func handle(_ event: DeviceEvent) {
        lastEvent = event.description
        guard let profile = store?.activeProfile else { return }

        switch event {
        case .connected:
            connected = true
            pushProfile()

        case .disconnected:
            connected = false
            device = nil

        case .firmwareVersion(let v): firmware = v
        case .serialNumber(let s):    serial = s

        case .buttonPress(let id, let pressed):
            guard pressed else { return }
            // IDs 1–8 observed as physical buttons; 9–14 are knob presses
            if id >= 1 && id <= 8 {
                ActionEngine.perform(profile.buttons[id - 1].action)
            } else if id >= 9 && id <= 14 {
                ActionEngine.perform(profile.knobs[id - 9].press)
            }

        case .knobRotate(let id, let delta):
            guard id >= 1 && id <= 6 else { return }
            let knob = profile.knobs[id - 1]
            ActionEngine.perform(delta > 0 ? knob.clockwise : knob.counterClockwise)

        case .touchStart(let x, let y, _):
            // Map touch to the tile grid and run its action
            let col = (x - RazerStreamController.centerXOffset) / RazerStreamController.buttonSize
            let row = y / RazerStreamController.buttonSize
            let cols = RazerStreamController.buttonColumns
            if col >= 0 && col < cols && row >= 0 && row < RazerStreamController.buttonRows {
                let idx = row * cols + col
                ActionEngine.perform(profile.tiles[idx].action)
            }

        default:
            break
        }
    }

    // MARK: - Push profile to device

    func pushProfile() {
        guard let device, let profile = store?.activeProfile else { return }
        try? device.send(.setBrightness(profile.brightness))
        for (i, tile) in profile.tiles.enumerated() {
            let rgb565 = TileRenderer.render(tile)
            try? device.send(.setButtonImage(button: i, rgb565: rgb565))
        }
    }
}
