import Foundation
import RazerStreamKit

// Owns the device connection for the app's lifetime: connects, auto-reconnects,
// pushes the current page's layout, and routes events to the ActionEngine.

@MainActor
final class DeviceManager: ObservableObject {

    @Published var connected = false
    @Published var firmware: String = "—"
    @Published var serial: String = "—"
    @Published var lastEvent: String = "—"

    private var device: RazerStreamDevice?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    weak var store: ProfileStore?

    func start(store: ProfileStore) {
        self.store = store
        connectLoop()
    }

    func stop() {
        eventTask?.cancel()
        reconnectTask?.cancel()
        pushTask?.cancel()
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
            self?.connected = false
            self?.device = nil
        }
    }

    // MARK: - Event routing

    private func handle(_ event: DeviceEvent) {
        lastEvent = event.description
        guard let store else { return }
        let page = store.currentPage

        switch event {
        case .connected:
            connected = true
            pushCurrentPage()

        case .disconnected:
            connected = false
            device = nil

        case .firmwareVersion(let v): firmware = v
        case .serialNumber(let s):    serial = s

        case .buttonPress(let id, let pressed):
            guard pressed else { return }
            // IDs 1–8 are physical buttons; 9–14 are knob presses
            if id >= 1 && id <= 8 {
                run(page.buttons[id - 1].action)
            } else if id >= 9 && id <= 14 {
                run(page.knobs[id - 9].press)
            }

        case .knobRotate(let id, let delta):
            guard id >= 1 && id <= 6 else { return }
            let knob = page.knobs[id - 1]
            run(delta > 0 ? knob.clockwise : knob.counterClockwise)

        case .touchStart(let x, let y, _):
            let col = (x - RazerStreamController.centerXOffset) / RazerStreamController.buttonSize
            let row = y / RazerStreamController.buttonSize
            let cols = RazerStreamController.buttonColumns
            if col >= 0 && col < cols && row >= 0 && row < RazerStreamController.buttonRows {
                run(page.tiles[row * cols + col].action)
            }

        default:
            break
        }
    }

    private func run(_ action: ControlAction) {
        ActionEngine.perform(action) { [weak self] nav in
            guard let self, let store = self.store else { return }
            switch nav {
            case .goto(let p): store.goToPage(p)
            case .next:        store.goToPage(store.currentPageIndex + 1)
            case .prev:        store.goToPage(store.currentPageIndex - 1)
            }
            self.pushCurrentPage()
        }
    }

    // MARK: - Push current page to device

    func pushCurrentPage() {
        guard let device, let store else { return }
        let profile = store.activeProfile
        let page = store.currentPage

        // Pace writes: blasting framebuffers back-to-back overruns the
        // device's serial buffer and nothing renders.
        pushTask?.cancel()
        pushTask = Task {
            try? device.send(.setBrightness(profile.brightness))
            try? await Task.sleep(for: .milliseconds(60))

            for (i, tile) in page.tiles.enumerated() {
                if Task.isCancelled { return }
                try? device.send(.setButtonImage(button: i, rgb565: TileRenderer.render(tile)))
                try? await Task.sleep(for: .milliseconds(60))
            }

            // Knob zones: 0–2 left strip (x=0), 3–5 right strip (x=420)
            for (i, knob) in page.knobs.enumerated() {
                if Task.isCancelled { return }
                let x = i < 3 ? 0 : RazerStreamController.centerXOffset + RazerStreamController.centerWidth
                let y = (i % 3) * 90
                try? device.send(.setDisplayImage(
                    display: .center, x: x, y: y, w: 60, h: 90,
                    rgb565: TileRenderer.renderKnobZone(knob, index: i)
                ))
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }
}
