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
    private var liveTileTask: Task<Void, Never>?
    private var idleCheckTask: Task<Void, Never>?
    private let appSwitchMonitor = AppSwitchMonitor()
    weak var store: ProfileStore?

    // Runtime control state (not persisted)
    @Published var toggleStates: [String: Bool] = [:]   // "p0-t3" → on/off
    private var activeTouches: [Int: Int] = [:]          // touchID → tile index
    private var shiftReturnPage: Int?

    // Two-finger swipe: remembers where each touch started (x position and
    // the page that was current then) until it lifts, so touchEnd can tell
    // a swipe from a tap by how far that touch travelled.
    private var touchOrigin: [Int: (x: Int, page: Int)] = [:]
    private static let swipeThreshold = 150   // out of 480 total screen width

    // Knob acceleration: two rotate events on the same knob closer together
    // than this count as a fast turn and step the assigned action further.
    private var lastKnobRotate: [Int: Date] = [:]
    private static let fastTurnInterval: TimeInterval = 0.12

    // Idle dimming
    private var lastInputAt = Date()
    private var isDimmed = false

    // Fires a haptic tick only when the page actually changed since the
    // last push, not on every redraw (toggle flips, brightness steps,
    // Redraw button); compared by id since index alone can be recycled
    // by page deletes/reorders.
    private var lastPushedPageID: Page.ID?

    func toggleKey(tile: Int) -> String { "p\(store?.currentPageIndex ?? 0)-t\(tile)" }
    func toggleKey(button: Int) -> String { "p\(store?.currentPageIndex ?? 0)-b\(button)" }

    func start(store: ProfileStore) {
        self.store = store
        connectLoop()
        startLiveTileClock()
        startIdleCheck()
        appSwitchMonitor.start(store: store, deviceManager: self)
    }

    func stop() {
        eventTask?.cancel()
        reconnectTask?.cancel()
        pushTask?.cancel()
        liveTileTask?.cancel()
        idleCheckTask?.cancel()
        appSwitchMonitor.stop()
        device?.close()
        device = nil
        connected = false
    }

    // MARK: - Idle dimming

    private func startIdleCheck() {
        idleCheckTask?.cancel()
        idleCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                self?.checkIdle()
            }
        }
    }

    private func checkIdle() {
        guard IdleDimming.isEnabled, connected, !isDimmed, let device else { return }
        let timeout = TimeInterval(IdleDimming.minutes * 60)
        guard timeout > 0, Date().timeIntervalSince(lastInputAt) >= timeout else { return }
        isDimmed = true
        try? device.send(.setBrightness(1))
    }

    /// Marks real device input (button, knob, touch); wakes the panel back
    /// to its configured brightness first, if it had dimmed for being idle.
    private func noteInput() {
        lastInputAt = Date()
        guard isDimmed, let device, let store else { return }
        isDimmed = false
        try? device.send(.setBrightness(store.activeProfile.brightness))
    }

    // MARK: - Live tiles (self-updating content, e.g. the clock)

    /// Redraws every clock tile on the current page once a minute, timed to
    /// land right on the minute boundary so it changes exactly when a real
    /// clock would.
    private func startLiveTileClock() {
        liveTileTask?.cancel()
        liveTileTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                let secondsIntoMinute = Calendar.current.component(.second, from: now)
                let delay = Double(60 - secondsIntoMinute)
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                self.refreshLiveTiles()
            }
        }
    }

    private func refreshLiveTiles() {
        guard connected, let store else { return }
        let page = store.currentPage
        for (i, tile) in page.tiles.enumerated() where tile.liveContent != .none {
            pushTile(i)
        }
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
            // Stream ended; tear down fully so the reconnect poll starts clean
            guard let self else { return }
            self.connected = false
            self.device?.close()
            self.device = nil
            self.pushTask?.cancel()
        }
    }

    // MARK: - Event routing

    private func handle(_ event: DeviceEvent) {
        lastEvent = event.description
        guard let store else { return }
        let page = store.resolvedCurrentPage

        switch event {
        case .connected:
            connected = true
            pushCurrentPage(choreography: true)

        case .disconnected:
            connected = false
            pushTask?.cancel()
            device?.close()
            device = nil
            // Runtime state is per-session; clear so a reconnect starts fresh
            toggleStates.removeAll()
            activeTouches.removeAll()
            touchOrigin.removeAll()
            shiftReturnPage = nil
            isDimmed = false

        case .firmwareVersion(let v): firmware = v
        case .serialNumber(let s):    serial = s

        case .buttonPress(let id, let pressed):
            // Device enumerates knob presses first: IDs 1–3 left knobs
            // top→bottom, 4–6 right knobs top→bottom, then 7–14 are the
            // eight physical buttons left→right. (Verified on hardware.)
            noteInput()
            if pressed { HapticFeedback.trigger(on: device) }
            if id >= 1 && id <= 6 {
                if pressed { run(page.knobs[id - 1].press) }
            } else if id >= 7 && id <= 14 {
                handleButton(index: id - 7, pressed: pressed, page: page)
            }

        case .knobRotate(let id, let delta):
            noteInput()
            guard id >= 1 && id <= 6 else { return }
            let knob = page.knobs[id - 1]
            let now = Date()
            let sinceLast = lastKnobRotate[id].map { now.timeIntervalSince($0) } ?? .infinity
            lastKnobRotate[id] = now
            let amount = sinceLast < Self.fastTurnInterval ? 3 : 1
            run(delta > 0 ? knob.clockwise : knob.counterClockwise, amount: amount)

        case .touchStart(let x, let y, let touchID):
            noteInput()
            if touchOrigin[touchID] == nil {
                touchOrigin[touchID] = (x, store.currentPageIndex)
            }
            // Only fire on the first event of this touch (device streams
            // touchStart repeatedly while a finger moves)
            guard activeTouches[touchID] == nil else { return }
            let col = (x - RazerStreamController.centerXOffset) / RazerStreamController.buttonSize
            let row = y / RazerStreamController.buttonSize
            let cols = RazerStreamController.buttonColumns
            guard col >= 0, col < cols, row >= 0, row < RazerStreamController.buttonRows else { return }
            let idx = row * cols + col
            activeTouches[touchID] = idx
            HapticFeedback.trigger(on: device)
            handleTilePress(index: idx, page: page)

        case .touchEnd(let x, _, let touchID):
            noteInput()
            if let idx = activeTouches.removeValue(forKey: touchID) {
                handleTileRelease(index: idx, page: page)
            }
            // Two-finger swipe: if another touch was still down when this one
            // started, and this one travelled far enough horizontally, treat
            // it as a page swipe rather than just a lifted tap.
            if let origin = touchOrigin.removeValue(forKey: touchID), !touchOrigin.isEmpty {
                let dx = x - origin.x
                if abs(dx) >= Self.swipeThreshold {
                    store.goToPage(origin.page + (dx < 0 ? 1 : -1))
                    pushCurrentPage()
                }
            }

        default:
            break
        }
    }

    // MARK: - Behavior modes

    private func handleTilePress(index: Int, page: Page) {
        let tile = page.tiles[index]
        switch tile.mode {
        case .tap, .momentary:
            run(tile.action)
        case .toggle:
            let key = toggleKey(tile: index)
            let nowOn = !(toggleStates[key] ?? false)
            toggleStates[key] = nowOn
            run(nowOn ? tile.action : tile.releaseAction)
            pushTile(index)   // redraw with alt icon / state ring
        case .shiftPage(let target):
            shiftReturnPage = store?.currentPageIndex
            store?.goToPage(target)
            pushCurrentPage()
        }
    }

    private func handleTileRelease(index: Int, page: Page) {
        let tile = page.tiles[index]
        switch tile.mode {
        case .momentary:
            run(tile.releaseAction)
        case .shiftPage:
            returnFromShift()
        default:
            break
        }
    }

    private func handleButton(index: Int, pressed: Bool, page: Page) {
        let button = page.buttons[index]
        switch button.mode {
        case .tap:
            if pressed { run(button.action) }
        case .momentary:
            run(pressed ? button.action : button.releaseAction)
        case .toggle:
            guard pressed else { return }
            let key = toggleKey(button: index)
            let nowOn = !(toggleStates[key] ?? false)
            toggleStates[key] = nowOn
            run(nowOn ? button.action : button.releaseAction)
            // LED shows state: configured color when on, off when off
            if index > 0, let device {
                let (r, g, b) = nowOn ? Self.rgb(fromHex: button.ledHex) : (0, 0, 0)
                try? device.send(.setButtonColor(button: 7 + index, r: r, g: g, b: b))
            }
        case .shiftPage(let target):
            if pressed {
                shiftReturnPage = store?.currentPageIndex
                store?.goToPage(target)
                pushCurrentPage()
            } else {
                returnFromShift()
            }
        }
    }

    private func returnFromShift() {
        if let back = shiftReturnPage {
            shiftReturnPage = nil
            store?.goToPage(back)
            pushCurrentPage()
        }
    }

    /// Redraw a single tile (used when a toggle flips state).
    private func pushTile(_ index: Int) {
        guard let device, let store else { return }
        let tile = store.currentPage.tiles[index]
        let isOn = toggleStates[toggleKey(tile: index)] ?? false
        try? device.send(.setButtonImage(
            button: index,
            rgb565: TileRenderer.render(tile, toggledOn: isOn)
        ))
    }

    private func run(_ action: ControlAction, amount: Int = 1) {
        ActionEngine.perform(action, amount: amount) { [weak self] nav in
            guard let self, let store = self.store else { return }
            switch nav {
            case .goto(let p): store.goToPage(p)
            case .next:        store.goToPage(store.currentPageIndex + 1)
            case .prev:        store.goToPage(store.currentPageIndex - 1)
            }
            self.pushCurrentPage()
        } deviceHandler: { [weak self] adjustment, amount in
            guard let self, let store = self.store else { return }
            let step = amount
            let current = Int(store.activeProfile.brightness)
            let next: Int
            switch adjustment {
            case .brightnessUp:   next = min(Int(maxBrightness), current + step)
            case .brightnessDown: next = max(0, current - step)
            }
            store.updateActive { $0.brightness = UInt8(next) }
            self.pushCurrentPage()
        }
    }

    // MARK: - Push current page to device

    /// Draws the current page onto the device; tiles, knob strips, and button
    /// LEDs. Pass choreography: true on connect to run the loading sweep plus
    /// an LED cascade as a hardware self-test.
    func pushCurrentPage(choreography: Bool = false) {
        guard let device, let store else { return }
        let profile = store.activeProfile
        let page = store.resolvedCurrentPage

        // A haptic tick confirms an actual page change (shift-hold, page
        // nav action, sidebar click, auto app-switch) without buzzing on
        // every redraw (toggle flips, brightness steps, Redraw button); the
        // initial connect draw is excluded too, since it has its own
        // cascade/fade-in welcome already.
        let isPageChange = !choreography && page.id != lastPushedPageID
        lastPushedPageID = page.id

        // Pace writes; blasting framebuffers back to back overruns the
        // device's serial buffer and nothing renders
        pushTask?.cancel()
        pushTask = Task {
            if choreography {
                await self.runLEDCascade(device: device, page: page)
                await self.fadeInBrightness(device: device, to: profile.brightness)
            } else {
                try? device.send(.setBrightness(profile.brightness))
                try? await Task.sleep(for: .milliseconds(60))
            }

            for (i, tile) in page.tiles.enumerated() {
                if Task.isCancelled { return }
                let isOn = toggleStates[toggleKey(tile: i)] ?? false
                try? device.send(.setButtonImage(button: i, rgb565: TileRenderer.render(tile, toggledOn: isOn)))
                try? await Task.sleep(for: .milliseconds(60))
            }

            // Knob zones; 0 to 2 left strip (x=0), 3 to 5 right strip (x=420)
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

            // Physical button LEDs (device IDs 7 to 14). Index 0 / ID 7 is the
            // status light; the device manages it, never write it.
            for (i, button) in page.buttons.enumerated() where i > 0 {
                if Task.isCancelled { return }
                let (r, g, b) = Self.rgb(fromHex: button.ledHex)
                try? device.send(.setButtonColor(button: 7 + i, r: r, g: g, b: b))
                try? await Task.sleep(for: .milliseconds(20))
            }

            if isPageChange { HapticFeedback.trigger(on: device) }
        }
    }

    /// Ramps brightness up from 0 instead of jumping straight to the target;
    /// only used on connect, so the panel wakes in gradually rather than
    /// snapping to full brightness the instant the handshake completes.
    private func fadeInBrightness(device: RazerStreamDevice, to target: UInt8) async {
        guard target > 0 else {
            try? device.send(.setBrightness(0))
            return
        }
        let steps = min(Int(target), 5)
        for step in 1...steps {
            if Task.isCancelled { return }
            try? device.send(.setBrightness(UInt8(Int(target) * step / steps)))
            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    /// Fires a haptic pattern once, on demand, from Settings > Haptics; goes
    /// straight to the device rather than through HapticFeedback.trigger, so
    /// it works regardless of the enabled toggle (the Test button is itself
    /// gated on that toggle in the UI).
    func testHaptic(_ pattern: Haptic) {
        try? device?.send(.vibrate(pattern))
    }

    /// Full self-test: a vivid pattern across every tile and knob strip while
    /// the LEDs sweep, then restores the real page. Runs on demand and can be
    /// triggered from the Device menu, toolbar, or menu bar.
    func testDevice() {
        guard let device, let store else { return }
        let page = store.currentPage
        pushTask?.cancel()
        pushTask = Task {
            try? device.send(.setBrightness(10))
            try? await Task.sleep(for: .milliseconds(40))

            // Paint the screen test pattern across all 12 tiles; paced slow
            // enough that you can watch each tile land in turn
            for i in 0..<page.tiles.count {
                if Task.isCancelled { return }
                try? device.send(.setButtonImage(button: i, rgb565: TileRenderer.renderTestTile(index: i)))
                try? await Task.sleep(for: .milliseconds(90))
            }
            // Test cards on the six knob strips
            for i in 0..<page.knobs.count {
                if Task.isCancelled { return }
                let x = i < 3 ? 0 : RazerStreamController.centerXOffset + RazerStreamController.centerWidth
                let y = (i % 3) * 90
                try? device.send(.setDisplayImage(
                    display: .center, x: x, y: y, w: 60, h: 90,
                    rgb565: TileRenderer.renderKnobTestZone(index: i)
                ))
                try? await Task.sleep(for: .milliseconds(90))
            }

            // LED rainbow sweep over the top of the screen pattern
            await self.runLEDCascade(device: device, page: page)

            // Hold the pattern a beat, then restore the real page
            try? await Task.sleep(for: .milliseconds(700))
            self.pushCurrentPage()
        }
    }

    private func runLEDCascade(device: RazerStreamDevice, page: Page) async {
        let wave: [(UInt8, UInt8, UInt8)] = [
            (255, 40, 40), (255, 150, 30), (240, 230, 40), (60, 210, 90),
            (50, 190, 220), (60, 90, 240), (170, 70, 230),
        ]

        // Two visible passes of the rainbow marching across buttons 2 to 8,
        // slow enough to actually watch; then settle to configured colors
        for pass in 0..<2 {
            for i in 1..<8 {
                if Task.isCancelled { return }
                let (r, g, b) = wave[(i - 1 + pass) % wave.count]
                try? device.send(.setButtonColor(button: 7 + i, r: r, g: g, b: b))
                try? await Task.sleep(for: .milliseconds(160))
            }
        }
        try? await Task.sleep(for: .milliseconds(300))
        for i in 1..<8 {
            if Task.isCancelled { return }
            let (r, g, b) = Self.rgb(fromHex: page.buttons[i].ledHex)
            try? device.send(.setButtonColor(button: 7 + i, r: r, g: g, b: b))
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func rgb(fromHex hex: String) -> (UInt8, UInt8, UInt8) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }
}
