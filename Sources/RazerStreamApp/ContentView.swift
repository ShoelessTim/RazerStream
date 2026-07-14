import SwiftUI
import RazerStreamKit

enum Selection: Equatable {
    case tile(Int), knob(Int), button(Int)
}

struct ContentView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var selection: Selection?

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                VStack(spacing: 14) {
                    pageBar
                    deviceMirror
                    physicalButtonRow
                    Spacer(minLength: 0)
                }
                .padding()
                .frame(minWidth: 560)

                inspector
                    .frame(minWidth: 300, maxWidth: 360)
            }

            statusBar
        }
        .frame(minWidth: 900, minHeight: 560)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    deviceManager.testDevice()
                } label: {
                    Label("Test Device", systemImage: "wand.and.rays")
                }
                .disabled(!deviceManager.connected)
                .help("Run the LED sweep self-test")

                Button {
                    deviceManager.pushCurrentPage()
                } label: {
                    Label("Redraw", systemImage: "arrow.clockwise")
                }
                .disabled(!deviceManager.connected)
                .help("Redraw the current page on the device")
            }
        }
    }

    // MARK: - Status bar; lives at the bottom of the window

    @State private var axGranted = ActionEngine.hasAccessibility
    private let axTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(deviceManager.connected ? .green : .red)
                .frame(width: 8, height: 8)
            Text(deviceManager.connected
                 ? "Connected · fw \(deviceManager.firmware)"
                 : "Waiting for device…")
                .font(.caption)
            if deviceManager.connected {
                Text(deviceManager.serial)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            if !axGranted {
                // Keystrokes and media keys need this; chip opens the right pane
                Button {
                    ActionEngine.requestAccessibility()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Keys need Accessibility; click to grant", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }

            Spacer()
            Text(deviceManager.lastEvent)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .onReceive(axTimer) { _ in
            axGranted = ActionEngine.hasAccessibility
        }
    }

    // MARK: - Pages

    private var pageBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(store.activeProfile.pages.enumerated()), id: \.element.id) { idx, page in
                Button {
                    store.goToPage(idx)
                    deviceManager.pushCurrentPage()
                } label: {
                    Text(page.name)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(idx == store.currentPageIndex
                                      ? Color.accentColor.opacity(0.25) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Button { store.addPage(); deviceManager.pushCurrentPage() } label: {
                Image(systemName: "plus")
            }
            if store.activeProfile.pages.count > 1 {
                Button(role: .destructive) {
                    store.deleteCurrentPage()
                    deviceManager.pushCurrentPage()
                } label: {
                    Image(systemName: "trash")
                }
            }
            Spacer()
        }
    }

    // MARK: - Device mirror

    private var deviceMirror: some View {
        let page = store.currentPage
        return HStack(spacing: 10) {
            knobColumn(indices: [0, 1, 2], page: page)
            tileGrid(page: page)
            knobColumn(indices: [3, 4, 5], page: page)
        }
    }

    private func tileGrid(page: Page) -> some View {
        let cols = RazerStreamController.buttonColumns
        return VStack(spacing: 8) {
            ForEach(0..<RazerStreamController.buttonRows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        tileView(page.tiles[idx], index: idx)
                    }
                }
            }
        }
    }

    private func tileView(_ tile: TileConfig, index: Int) -> some View {
        Button { selection = .tile(index) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: tile.colorHex))
                if let path = tile.imagePath, let img = NSImage(contentsOfFile: path) {
                    Image(nsImage: img)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if let symbol = tile.sfSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                }
                VStack {
                    Spacer()
                    Text(tile.label.isEmpty && tile.sfSymbol == nil && tile.imagePath == nil
                         ? "\(index)" : tile.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 4)
                }
            }
            .frame(width: 84, height: 84)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selection == .tile(index) ? Color.accentColor : .clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }

    private func knobColumn(indices: [Int], page: Page) -> some View {
        VStack(spacing: 8) {
            ForEach(indices, id: \.self) { i in
                let knob = page.knobs[i]
                Button { selection = .knob(i) } label: {
                    VStack(spacing: 4) {
                        if let symbol = knob.sfSymbol {
                            Image(systemName: symbol).font(.system(size: 16))
                        } else {
                            Image(systemName: "dial.medium").font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        Text(knob.label.isEmpty ? "K\(i + 1)" : knob.label)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 84)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "16161a")))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selection == .knob(i) ? Color.accentColor : .clear, lineWidth: 3)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var physicalButtonRow: some View {
        let page = store.currentPage
        return HStack(spacing: 10) {
            ForEach(0..<8, id: \.self) { i in
                Button { selection = .button(i) } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "222228"))
                            .frame(width: 36, height: 36)
                        // LED ring: green status light on button 1, configured color elsewhere
                        Circle()
                            .stroke(i == 0 ? Color.green : Color(hex: page.buttons[i].ledHex),
                                    lineWidth: 2)
                            .frame(width: 30, height: 30)
                        if page.buttons[i].action != .none {
                            Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                                .offset(y: 12)
                        }
                        Text("\(i + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .overlay(
                        Circle().stroke(selection == .button(i) ? Color.accentColor : .clear, lineWidth: 3)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.leading, 70)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        switch selection {
        case .tile(let i):   TileInspector(tileIndex: i).padding()
        case .knob(let i):   KnobInspector(knobIndex: i).padding()
        case .button(let i): ButtonInspector(buttonIndex: i).padding()
        case nil:
            VStack {
                Text("Select a tile, knob, or button to edit")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Reusable action editor

struct ActionEditor: View {
    let title: String
    @Binding var action: ControlAction
    @EnvironmentObject var store: ProfileStore

    enum Kind: String, CaseIterable {
        case none = "None"
        case launchApp = "Open App"
        case openURL = "Open URL"
        case shell = "Shell Command"
        case script = "AppleScript"
        case keystroke = "Keystroke"
        case mediaPlayPause = "Play / Pause"
        case mediaNext = "Next Track"
        case mediaPrevious = "Previous Track"
        case volumeUp = "Volume +"
        case volumeDown = "Volume −"
        case volumeMute = "Mute"
        case gotoPage = "Go to Page"
        case nextPage = "Next Page"
        case prevPage = "Previous Page"
        case showApp = "Show RazerStream"
    }

    @State private var kind: Kind = .none
    @State private var param: String = ""
    @State private var pageIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
            }
            .labelsHidden()
            .onChange(of: kind) { syncOut() }

            switch kind {
            case .launchApp:
                HStack {
                    TextField("/Applications/…app", text: $param)
                        .onChange(of: param) { syncOut() }
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.application]
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        if panel.runModal() == .OK, let url = panel.url {
                            param = url.path
                            syncOut()
                        }
                    }
                }
            case .openURL:
                TextField("https://…", text: $param).onChange(of: param) { syncOut() }
            case .shell:
                TextField("Command", text: $param).onChange(of: param) { syncOut() }
            case .script:
                TextField("AppleScript", text: $param).onChange(of: param) { syncOut() }
            case .keystroke:
                KeystrokeRecorder(combo: $param)
                    .onChange(of: param) { syncOut() }
            case .gotoPage:
                Picker("", selection: $pageIndex) {
                    ForEach(0..<store.activeProfile.pages.count, id: \.self) { i in
                        Text(store.activeProfile.pages[i].name).tag(i)
                    }
                }
                .labelsHidden()
                .onChange(of: pageIndex) { syncOut() }
            default:
                EmptyView()
            }
        }
        .onAppear(perform: syncIn)
        .onChange(of: action) { syncIn() }
    }

    private func syncIn() {
        switch action {
        case .none:                kind = .none;       param = ""
        case .launchApp(let p):    kind = .launchApp;  param = p
        case .openURL(let u):      kind = .openURL;    param = u
        case .shellCommand(let c): kind = .shell;      param = c
        case .appleScript(let s):  kind = .script;     param = s
        case .keystroke(let k):    kind = .keystroke;  param = k
        case .mediaPlayPause:      kind = .mediaPlayPause
        case .mediaNext:           kind = .mediaNext
        case .mediaPrevious:       kind = .mediaPrevious
        case .volumeUp:            kind = .volumeUp
        case .volumeDown:          kind = .volumeDown
        case .volumeMute:          kind = .volumeMute
        case .gotoPage(let p):     kind = .gotoPage;   pageIndex = p
        case .nextPage:            kind = .nextPage
        case .prevPage:            kind = .prevPage
        case .showApp:             kind = .showApp
        }
    }

    private func syncOut() {
        switch kind {
        case .none:       action = .none
        case .launchApp:  action = .launchApp(path: param)
        case .openURL:    action = .openURL(param)
        case .shell:      action = .shellCommand(param)
        case .script:     action = .appleScript(param)
        case .keystroke:  action = .keystroke(param)
        case .mediaPlayPause: action = .mediaPlayPause
        case .mediaNext:      action = .mediaNext
        case .mediaPrevious:  action = .mediaPrevious
        case .volumeUp:   action = .volumeUp
        case .volumeDown: action = .volumeDown
        case .volumeMute: action = .volumeMute
        case .gotoPage:   action = .gotoPage(pageIndex)
        case .nextPage:   action = .nextPage
        case .prevPage:   action = .prevPage
        case .showApp:    action = .showApp
        }
    }
}

// MARK: - SF Symbols picker

struct SymbolPicker: View {
    @Binding var symbol: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    static let library: [String] = [
        // Media
        "play.fill", "pause.fill", "stop.fill", "backward.fill", "forward.fill",
        "speaker.wave.3.fill", "speaker.slash.fill", "music.note", "mic.fill", "mic.slash.fill",
        "headphones", "hifispeaker.fill", "radio.fill", "tv.fill",
        // Streaming / video
        "video.fill", "video.slash.fill", "camera.fill", "record.circle", "dot.radiowaves.left.and.right",
        "rectangle.on.rectangle", "person.crop.rectangle", "theatermasks.fill", "wand.and.stars",
        // Apps & system
        "app.fill", "terminal.fill", "safari.fill", "envelope.fill", "message.fill",
        "phone.fill", "calendar", "folder.fill", "doc.fill", "gear",
        "lock.fill", "lock.open.fill", "power", "restart", "moon.fill",
        // Arrows & nav
        "arrow.up", "arrow.down", "arrow.left", "arrow.right",
        "arrow.clockwise", "arrow.counterclockwise", "arrow.uturn.left",
        "chevron.left", "chevron.right", "house.fill",
        // Symbols & misc
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "drop.fill",
        "leaf.fill", "sun.max.fill", "cloud.fill", "snowflake", "sparkles",
        "bell.fill", "tag.fill", "bookmark.fill", "flag.fill", "pin.fill",
        "lightbulb.fill", "lamp.desk.fill", "fanblades.fill", "thermometer.medium",
        // Numbers & grid
        "1.circle.fill", "2.circle.fill", "3.circle.fill", "4.circle.fill",
        "square.grid.2x2.fill", "square.grid.3x3.fill", "circle.grid.cross.fill",
        // Hands & people
        "hand.thumbsup.fill", "hand.raised.fill", "person.fill", "person.2.fill",
        // Games & fun
        "gamecontroller.fill", "dice.fill", "puzzlepiece.fill", "trophy.fill",
        "gift.fill", "party.popper.fill", "birthday.cake.fill",
        // Work
        "briefcase.fill", "clock.fill", "timer", "stopwatch.fill", "alarm.fill",
        "chart.bar.fill", "chart.pie.fill", "dollarsign.circle.fill",
        "cart.fill", "creditcard.fill", "printer.fill", "scissors",
        // Devices
        "keyboard.fill", "desktopcomputer", "laptopcomputer", "display",
        "wifi", "antenna.radiowaves.left.and.right", "bluetooth", "battery.100percent",
    ]

    private var filtered: [String] {
        search.isEmpty
            ? Self.library
            : Self.library.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search symbols… (or type any SF Symbol name)", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.adaptive(minimum: 44)), count: 8), spacing: 10) {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            symbol = name
                            dismiss()
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 20))
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
                .padding(4)
            }

            HStack {
                Button("Use typed name") {
                    if !search.isEmpty { symbol = search; dismiss() }
                }
                .disabled(search.isEmpty)
                Spacer()
                Button("Clear symbol") { symbol = ""; dismiss() }
                Button("Cancel") { dismiss() }
            }
        }
        .padding()
        .frame(width: 480, height: 420)
    }
}

// MARK: - Tile editor

struct TileInspector: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    let tileIndex: Int

    @State private var label = ""
    @State private var color = Color(hex: "333333")
    @State private var sfSymbol = ""
    @State private var altSymbol = ""
    @State private var imagePath = ""
    @State private var action: ControlAction = .none
    @State private var releaseAction: ControlAction = .none
    @State private var mode: ControlMode = .tap
    @State private var showSymbolPicker = false

    var body: some View {
        Form {
            Section("Tile \(tileIndex) — \(store.currentPage.name)") {
                TextField("Label", text: $label)
                ColorPicker("Background", selection: $color, supportsOpacity: false)
                HStack {
                    if !sfSymbol.isEmpty {
                        Image(systemName: sfSymbol)
                        Text(sfSymbol).font(.caption)
                    } else {
                        Text("No icon").foregroundStyle(.secondary).font(.caption)
                    }
                    Spacer()
                    Button("Icon Library…") { showSymbolPicker = true }
                }
                HStack {
                    TextField("Custom image (optional)", text: $imagePath)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
                        if panel.runModal() == .OK, let url = panel.url {
                            imagePath = url.path
                        }
                    }
                }
            }
            Section("Behavior") {
                ModeEditor(mode: $mode, action: $action,
                           releaseAction: $releaseAction, altSymbol: $altSymbol)
            }
            Button("Apply") { apply() }
                .keyboardShortcut(.return)
        }
        .sheet(isPresented: $showSymbolPicker) {
            SymbolPicker(symbol: $sfSymbol)
        }
        .onAppear(perform: loadCurrent)
        .onChange(of: tileIndex) { loadCurrent() }
        .onChange(of: store.currentPageIndex) { loadCurrent() }
    }

    private func loadCurrent() {
        let tile = store.currentPage.tiles[tileIndex]
        label = tile.label
        color = Color(hex: tile.colorHex)
        sfSymbol = tile.sfSymbol ?? ""
        altSymbol = tile.altSymbol ?? ""
        imagePath = tile.imagePath ?? ""
        action = tile.action
        releaseAction = tile.releaseAction
        mode = tile.mode
    }

    private func apply() {
        store.updateCurrentPage { page in
            page.tiles[tileIndex] = TileConfig(
                label: label,
                colorHex: color.hexString,
                sfSymbol: sfSymbol.isEmpty ? nil : sfSymbol,
                altSymbol: altSymbol.isEmpty ? nil : altSymbol,
                imagePath: imagePath.isEmpty ? nil : imagePath,
                action: action,
                releaseAction: releaseAction,
                mode: mode
            )
        }
        deviceManager.pushCurrentPage()
    }
}

// MARK: - Knob editor

struct KnobInspector: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    let knobIndex: Int

    @State private var label = ""
    @State private var sfSymbol = ""
    @State private var clockwise: ControlAction = .none
    @State private var counterClockwise: ControlAction = .none
    @State private var press: ControlAction = .none
    @State private var showSymbolPicker = false

    var body: some View {
        Form {
            Section("Knob \(knobIndex + 1) (\(knobIndex < 3 ? "left" : "right") \(["top", "middle", "bottom"][knobIndex % 3]))") {
                TextField("Label", text: $label)
                HStack {
                    if !sfSymbol.isEmpty {
                        Image(systemName: sfSymbol)
                        Text(sfSymbol).font(.caption)
                    } else {
                        Text("No icon").foregroundStyle(.secondary).font(.caption)
                    }
                    Spacer()
                    Button("Icon Library…") { showSymbolPicker = true }
                }
            }
            Section("Actions") {
                ActionEditor(title: "Turn right (clockwise)", action: $clockwise)
                ActionEditor(title: "Turn left (counter-clockwise)", action: $counterClockwise)
                ActionEditor(title: "Press", action: $press)
            }
            Button("Apply") { apply() }
                .keyboardShortcut(.return)
        }
        .sheet(isPresented: $showSymbolPicker) {
            SymbolPicker(symbol: $sfSymbol)
        }
        .onAppear(perform: loadCurrent)
        .onChange(of: knobIndex) { loadCurrent() }
        .onChange(of: store.currentPageIndex) { loadCurrent() }
    }

    private func loadCurrent() {
        let knob = store.currentPage.knobs[knobIndex]
        label = knob.label
        sfSymbol = knob.sfSymbol ?? ""
        clockwise = knob.clockwise
        counterClockwise = knob.counterClockwise
        press = knob.press
    }

    private func apply() {
        store.updateCurrentPage { page in
            page.knobs[knobIndex] = KnobConfig(
                label: label,
                sfSymbol: sfSymbol.isEmpty ? nil : sfSymbol,
                clockwise: clockwise,
                counterClockwise: counterClockwise,
                press: press
            )
        }
        deviceManager.pushCurrentPage()
    }
}

// MARK: - Physical button editor

struct ButtonInspector: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    let buttonIndex: Int

    @State private var action: ControlAction = .none
    @State private var releaseAction: ControlAction = .none
    @State private var mode: ControlMode = .tap
    @State private var ledColor = Color.black

    private var isStatusLight: Bool { buttonIndex == 0 }

    var body: some View {
        Form {
            Section("Physical Button \(buttonIndex + 1)") {
                ModeEditor(mode: $mode, action: $action,
                           releaseAction: $releaseAction, altSymbol: nil)
                if isStatusLight {
                    Label("LED is the device status light — managed by the device",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ColorPicker("LED color", selection: $ledColor, supportsOpacity: false)
                }
            }
            Button("Apply") { apply() }
                .keyboardShortcut(.return)
        }
        .onAppear(perform: loadCurrent)
        .onChange(of: buttonIndex) { loadCurrent() }
        .onChange(of: store.currentPageIndex) { loadCurrent() }
    }

    private func loadCurrent() {
        let button = store.currentPage.buttons[buttonIndex]
        action = button.action
        releaseAction = button.releaseAction
        mode = button.mode
        ledColor = Color(hex: button.ledHex)
    }

    private func apply() {
        store.updateCurrentPage { page in
            page.buttons[buttonIndex] = ButtonConfig(
                action: action,
                releaseAction: releaseAction,
                mode: mode,
                ledHex: isStatusLight ? "000000" : ledColor.hexString
            )
        }
        deviceManager.pushCurrentPage()
    }
}

// MARK: - Helpers

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    /// "RRGGBB" for storage; sRGB-converted.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }
}
