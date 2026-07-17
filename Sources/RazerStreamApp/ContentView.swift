import SwiftUI
import Combine
import UniformTypeIdentifiers
import RazerStreamKit

enum Selection: Equatable {
    case tile(Int), knob(Int), button(Int)
}

/// Drag payload for reordering tiles within the grid, or moving one to a
/// different page via the sidebar; in-process only, so a synthesized
/// content type (not registered in Info.plist) is sufficient. The source
/// page id travels with the payload rather than being looked up at drop
/// time, since the current page could in principle change mid-drag.
struct TileDragPayload: Codable, Transferable {
    let sourceIndex: Int
    let sourcePageID: Page.ID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .razerStreamTile)
    }
}

extension UTType {
    static let razerStreamTile = UTType(exportedAs: "org.community.razerstream.tile")
}

struct ContentView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var selection: Selection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var dragTargetTileIndex: Int?
    @State private var hoveredSelection: Selection?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 280)
        } content: {
            // The mirror represents fixed physical hardware, so it is one
            // fixed-size unit (knobs, tiles, and buttons locked together) that
            // stays centered with generous margins. GeometryReader reports the
            // real viewport size so the content can be told to fill *at least*
            // that much (minWidth/minHeight, not maxWidth/maxHeight): a plain
            // maxWidth/maxHeight: .infinity inside a ScrollView fights the
            // ScrollView's own sizing model and only centers reliably on one
            // axis. With min sizing the content centers on both axes when
            // there is room, and scrolls instead of clipping when there isn't.
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 20) {
                        if !deviceManager.connected {
                            Label("No device connected; edits still apply once one is plugged in.",
                                  systemImage: "cable.connector.slash")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .frame(maxWidth: Self.mirrorWidth)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                        deviceUnit
                    }
                    .padding(28)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
            }
            .frame(minWidth: Self.mirrorWidth + 56)
            .animation(.easeInOut, value: deviceManager.connected)
        } detail: {
            inspector
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 380)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
        // Sized so all three columns fit at their minimums without ever
        // compressing into each other (170 sidebar + 572 content + 300 detail)
        .frame(minWidth: 1060, minHeight: 620)
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
        .sheet(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { presented in if !presented { hasCompletedOnboarding = true } }
        )) {
            OnboardingView()
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

    // MARK: - Sidebar (pages)

    /// The sidebar selects a page directly by id, since a page's index can
    /// shift out from under it (delete, reorder) between renders.
    private var selectedPageID: Binding<Page.ID?> {
        Binding(
            get: { store.currentPage.id },
            set: { newID in
                guard let newID,
                      let idx = store.activeProfile.pages.firstIndex(where: { $0.id == newID })
                else { return }
                store.goToPage(idx)
                deviceManager.pushCurrentPage()
            }
        )
    }

    private var sidebar: some View {
        List(selection: selectedPageID) {
            Section("Pages") {
                ForEach(store.activeProfile.pages) { page in
                    PageRow(page: page)
                        .tag(page.id)
                        .contextMenu {
                            if store.activeProfile.pages.count > 1 {
                                Button("Delete", role: .destructive) {
                                    store.deletePage(page.id)
                                    deviceManager.pushCurrentPage()
                                }
                            }
                        }
                }
                .onMove { indices, newOffset in
                    store.movePages(fromOffsets: indices, toOffset: newOffset)
                    deviceManager.pushCurrentPage()
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    store.addPage()
                    deviceManager.pushCurrentPage()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add Page")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Sidebar page row (double-click to rename, like Finder and Xcode)

private struct PageRow: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    let page: Page

    @State private var isEditing = false
    @State private var draftName = ""
    @FocusState private var focused: Bool
    @State private var isDropTarget = false

    var body: some View {
        HStack {
            Image(systemName: "square.grid.3x2")
                .foregroundStyle(.secondary)
            if isEditing {
                TextField("Page name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { commit() }
            } else {
                Text(page.name)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            draftName = page.name
            isEditing = true
            focused = true
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused && isEditing { commit() }
        }
        .listRowBackground(isDropTarget ? Color.accentColor.opacity(0.15) : nil)
        .dropDestination(for: TileDragPayload.self) { items, _ in
            guard let payload = items.first, payload.sourcePageID != page.id else { return false }
            store.moveTile(from: payload.sourceIndex, sourcePageID: payload.sourcePageID, toPageID: page.id)
            deviceManager.pushCurrentPage()
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .animation(.easeInOut(duration: 0.1), value: isDropTarget)
    }

    private func commit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { store.renamePage(page.id, to: trimmed) }
        isEditing = false
    }
}

extension ContentView {
    // MARK: - Device mirror

    private var deviceMirror: some View {
        let page = store.currentPage
        return HStack(spacing: Self.knobGutter) {
            knobColumn(indices: [0, 1, 2], page: page)
            tileGrid(page: page)
            knobColumn(indices: [3, 4, 5], page: page)
        }
    }

    // One source of truth for the mirror's geometry so every piece stays
    // locked to every other piece; the tile grid, the knob columns, and the
    // physical button row all derive their positions from these.
    private static let tileSize: CGFloat = 84
    private static let tileGap: CGFloat = 8
    private static let knobColumnWidth: CGFloat = 54
    private static let knobGutter: CGFloat = 24
    // 4 tiles across plus 3 gaps between them
    static let tileGridWidth: CGFloat = 4 * tileSize + 3 * tileGap        // 360
    // left knob strip + gutter + tile grid + gutter + right knob strip
    static let mirrorWidth: CGFloat = 2 * (knobColumnWidth + knobGutter) + tileGridWidth  // 516

    /// The whole device as one rigid unit: knob columns, tile grid, and the
    /// physical button row locked together so they can never drift apart.
    private var deviceUnit: some View {
        VStack(spacing: 20) {
            deviceMirror
            physicalButtonRow
        }
        .fixedSize()
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
                    // Quantized to the tile panel's real 16-bit RGB565 depth,
                    // so this preview matches what the device actually shows
                    .fill(Color.quantizedToTilePanel(hex: tile.colorHex))
                if tile.liveContent == .clock {
                    clockFace()
                } else if let path = tile.imagePath, let img = NSImage(contentsOfFile: path) {
                    Image(nsImage: img)
                        .renderingMode(tile.iconTint ? .template : .original)
                        .resizable().scaledToFit()
                        .padding(tile.iconTint ? 18 : 0)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if let symbol = tile.sfSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                }
                if tile.liveContent == .none {
                    VStack {
                        Spacer()
                        Text(tile.label.isEmpty && tile.sfSymbol == nil && tile.imagePath == nil
                             ? "\(index)" : tile.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.bottom, 4)
                    }
                }
            }
            .frame(width: 84, height: 84)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selection == .tile(index) ? Color.accentColor
                        : (dragTargetTileIndex == index ? Color.accentColor.opacity(0.5)
                           : (hoveredSelection == .tile(index) ? Color.white.opacity(0.4) : .clear)),
                        lineWidth: 3
                    )
            )
            // Dock-style magnify on hover; a familiar Apple hover affordance
            // for a grid of tappable tiles
            .scaleEffect(hoveredSelection == .tile(index) && selection != .tile(index) ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredSelection = isHovering ? .tile(index)
                : (hoveredSelection == .tile(index) ? nil : hoveredSelection)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hoveredSelection)
        .animation(.easeInOut(duration: 0.12), value: selection)
        .draggable(TileDragPayload(sourceIndex: index, sourcePageID: store.currentPage.id))
        .dropDestination(for: TileDragPayload.self) { items, _ in
            guard let payload = items.first, payload.sourcePageID == store.currentPage.id else { return false }
            store.moveTile(from: payload.sourceIndex, to: index)
            deviceManager.pushCurrentPage()
            return true
        } isTargeted: { targeted in
            dragTargetTileIndex = targeted ? index
                : (dragTargetTileIndex == index ? nil : dragTargetTileIndex)
        }
    }

    /// Mirrors TileRenderer's clock face in the app window; ticks on its own
    /// so the preview matches what is drawn on the device.
    private func clockFace() -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .semibold))
                Text(context.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 10))
            }
            .foregroundStyle(.white)
        }
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
                            .stroke(
                                selection == .knob(i) ? Color.accentColor
                                : (hoveredSelection == .knob(i) ? Color.white.opacity(0.4) : .clear),
                                lineWidth: 3
                            )
                    )
                    .scaleEffect(hoveredSelection == .knob(i) && selection != .knob(i) ? 1.05 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredSelection = isHovering ? .knob(i)
                        : (hoveredSelection == .knob(i) ? nil : hoveredSelection)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hoveredSelection)
                .animation(.easeInOut(duration: 0.12), value: selection)
            }
        }
    }

    private var physicalButtonRow: some View {
        let page = store.currentPage
        // The eight buttons span exactly the tile-grid width and are inset by
        // one knob strip on each side, so the row is locked under the tiles
        // and stays centered within the mirror unit no matter what.
        return HStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { i in
                buttonView(index: i, page: page)
                if i < 7 { Spacer(minLength: 0) }
            }
        }
        .frame(width: Self.tileGridWidth)
        .padding(.horizontal, Self.knobColumnWidth + Self.knobGutter)
    }

    private func buttonView(index i: Int, page: Page) -> some View {
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
                Circle().stroke(
                    selection == .button(i) ? Color.accentColor
                    : (hoveredSelection == .button(i) ? Color.white.opacity(0.4) : .clear),
                    lineWidth: 3
                )
            )
            .scaleEffect(hoveredSelection == .button(i) && selection != .button(i) ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredSelection = isHovering ? .button(i)
                : (hoveredSelection == .button(i) ? nil : hoveredSelection)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hoveredSelection)
        .animation(.easeInOut(duration: 0.12), value: selection)
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
        case brightnessUp = "Brightness +"
        case brightnessDown = "Brightness −"
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
        case .brightnessUp:        kind = .brightnessUp
        case .brightnessDown:      kind = .brightnessDown
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
        case .brightnessUp:   action = .brightnessUp
        case .brightnessDown: action = .brightnessDown
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
    @State private var iconTint = false
    @State private var liveContent: LiveContent = .none
    @State private var action: ControlAction = .none
    @State private var releaseAction: ControlAction = .none
    @State private var mode: ControlMode = .tap
    @State private var showSymbolPicker = false

    var body: some View {
        Form {
            Section("Tile \(tileIndex) — \(store.currentPage.name)") {
                ColorPicker("Background", selection: $color, supportsOpacity: false)
                Picker("Content", selection: $liveContent) {
                    Text("Static").tag(LiveContent.none)
                    Text("Clock").tag(LiveContent.clock)
                }
                if liveContent == .clock {
                    Text("Shows the current time; updates on its own once a minute.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Label", text: $label)
                    LabeledContent("Icon") {
                        HStack(spacing: 8) {
                            Group {
                                if !sfSymbol.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: sfSymbol)
                                        Text(sfSymbol)
                                    }
                                } else if !imagePath.isEmpty {
                                    HStack(spacing: 4) {
                                        if let img = IconThumbnails.image(forPath: imagePath) {
                                            Image(nsImage: img)
                                                .renderingMode(iconTint ? .template : .original)
                                        }
                                        Text((imagePath as NSString).lastPathComponent)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                } else {
                                    Text("None").foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            Spacer(minLength: 8)
                            Button("Icon Library…") { showSymbolPicker = true }
                        }
                    }

                    HStack {
                        TextField("Custom image (optional)", text: $imagePath)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
                            if panel.runModal() == .OK, let url = panel.url {
                                imagePath = url.path
                                iconTint = false
                            }
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
        .formStyle(.grouped)
        .sheet(isPresented: $showSymbolPicker) {
            IconPicker(symbol: $sfSymbol, imagePath: $imagePath, tintIcon: $iconTint)
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
        iconTint = tile.iconTint
        liveContent = tile.liveContent
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
                iconTint: iconTint,
                liveContent: liveContent,
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
                LabeledContent("Icon") {
                    HStack(spacing: 8) {
                        Group {
                            if !sfSymbol.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: sfSymbol)
                                    Text(sfSymbol)
                                }
                            } else {
                                Text("None").foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        Spacer(minLength: 8)
                        Button("Icon Library…") { showSymbolPicker = true }
                    }
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
        .formStyle(.grouped)
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
        .formStyle(.grouped)
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

    /// Rounds a "RRGGBB" hex string down to what the device's 16-bit
    /// RGB565 tile panel can actually display (5 red bits, 6 green, 5
    /// blue) and back up, matching the exact bit truncation TileRenderer
    /// uses when it packs pixels for the wire. LEDs are true 8-bit and do
    /// not need this; only the tile panel is display-limited. Without this
    /// the on-screen preview shows colors the hardware cannot reproduce.
    static func quantizedToTilePanel(hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r8 = UInt8((v >> 16) & 0xFF), g8 = UInt8((v >> 8) & 0xFF), b8 = UInt8(v & 0xFF)

        let r5 = (r8 & 0xF8) >> 3, g6 = (g8 & 0xFC) >> 2, b5 = b8 >> 3
        let rOut = (r5 << 3) | (r5 >> 2)
        let gOut = (g6 << 2) | (g6 >> 4)
        let bOut = (b5 << 3) | (b5 >> 2)

        return Color(
            red: Double(rOut) / 255, green: Double(gOut) / 255, blue: Double(bOut) / 255
        )
    }
}
