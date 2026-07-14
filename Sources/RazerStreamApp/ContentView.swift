import SwiftUI
import RazerStreamKit

struct ContentView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var selectedTile: Int?

    var body: some View {
        HSplitView {
            VStack(spacing: 16) {
                statusBar
                tileGrid
                Spacer()
            }
            .padding()
            .frame(minWidth: 460)

            inspector
                .frame(minWidth: 280, maxWidth: 340)
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    // MARK: - Status

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(deviceManager.connected ? .green : .red)
                .frame(width: 10, height: 10)
            Text(deviceManager.connected
                 ? "Connected — fw \(deviceManager.firmware)"
                 : "Waiting for device…")
                .font(.callout)
            Spacer()
            Text(deviceManager.lastEvent)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tile grid (mirrors the device's 4×3 touch area)

    private var tileGrid: some View {
        let cols = RazerStreamController.buttonColumns
        let profile = store.activeProfile

        return VStack(spacing: 8) {
            ForEach(0..<RazerStreamController.buttonRows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        tileView(profile.tiles[idx], index: idx)
                    }
                }
            }
        }
    }

    private func tileView(_ tile: TileConfig, index: Int) -> some View {
        Button {
            selectedTile = index
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: tile.colorHex))
                Text(tile.label.isEmpty ? "\(index)" : tile.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 90, height: 90)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedTile == index ? Color.accentColor : .clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if let idx = selectedTile {
            TileInspector(tileIndex: idx)
                .padding()
        } else {
            VStack {
                Text("Select a tile to edit")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Tile editor

struct TileInspector: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    let tileIndex: Int

    @State private var label: String = ""
    @State private var colorHex: String = "333333"
    @State private var imagePath: String = ""
    @State private var actionKind: ActionKind = .none
    @State private var actionParam: String = ""

    enum ActionKind: String, CaseIterable {
        case none = "None"
        case launchApp = "Open App"
        case shell = "Shell Command"
        case script = "AppleScript"
    }

    var body: some View {
        Form {
            Section("Tile \(tileIndex)") {
                TextField("Label", text: $label)
                TextField("Color (hex)", text: $colorHex)
                HStack {
                    TextField("Image path (optional)", text: $imagePath)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            imagePath = url.path
                        }
                    }
                }
            }
            Section("Action") {
                Picker("Type", selection: $actionKind) {
                    ForEach(ActionKind.allCases, id: \.self) { Text($0.rawValue) }
                }
                if actionKind == .launchApp {
                    TextField("App path (/Applications/…app)", text: $actionParam)
                } else if actionKind == .shell {
                    TextField("Command", text: $actionParam)
                } else if actionKind == .script {
                    TextField("Script", text: $actionParam)
                }
            }
            Button("Apply") { apply() }
                .keyboardShortcut(.return)
        }
        .onAppear(perform: loadCurrent)
        .onChange(of: tileIndex) { loadCurrent() }
    }

    private func loadCurrent() {
        let tile = store.activeProfile.tiles[tileIndex]
        label = tile.label
        colorHex = tile.colorHex
        imagePath = tile.imagePath ?? ""
        switch tile.action {
        case .none:                    actionKind = .none;      actionParam = ""
        case .launchApp(let p):        actionKind = .launchApp; actionParam = p
        case .shellCommand(let c):     actionKind = .shell;     actionParam = c
        case .appleScript(let s):      actionKind = .script;    actionParam = s
        default:                       actionKind = .none;      actionParam = ""
        }
    }

    private func apply() {
        let action: ControlAction
        switch actionKind {
        case .none:      action = .none
        case .launchApp: action = .launchApp(path: actionParam)
        case .shell:     action = .shellCommand(actionParam)
        case .script:    action = .appleScript(actionParam)
        }
        store.updateActive { profile in
            profile.tiles[tileIndex] = TileConfig(
                label: label,
                colorHex: colorHex,
                imagePath: imagePath.isEmpty ? nil : imagePath,
                action: action
            )
        }
        deviceManager.pushProfile()
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
}
