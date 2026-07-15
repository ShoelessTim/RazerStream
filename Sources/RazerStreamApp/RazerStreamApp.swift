import SwiftUI

// Bridge so non-SwiftUI code (a device button firing the Show action) can ask
// the app to open or front the main window. The closure is captured once at
// launch from a SwiftUI context that has openWindow.
@MainActor
final class AppActions {
    static let shared = AppActions()
    var showMainWindow: (() -> Void)?
}

@main
struct RazerStreamApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var deviceManager = DeviceManager()
    @StateObject private var packManager = IconPackManager()

    // 0 = follow system (default), 1 = light, 2 = dark
    @AppStorage("appearanceMode") private var appearanceMode = 0

    init() {
        setbuf(stdout, nil)   // immediate debug output when piped to a file
    }

    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case 1:  return .light
        case 2:  return .dark
        default: return nil   // system
        }
    }

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Single Window (not WindowGroup); openWindow fronts the existing one
        // or reopens it if closed, and never spawns a duplicate. That is the
        // right model for a control panel.
        Window("RazerStream", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(deviceManager)
                .environmentObject(packManager)
                .preferredColorScheme(colorScheme)
                .onAppear {
                    // Bare binaries aren't foreground apps by default;
                    // promote ourselves so the window actually shows
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    deviceManager.start(store: store)
                    // Capture a reopen closure for non-SwiftUI callers
                    AppActions.shared.showMainWindow = {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .commands {
            CommandMenu("Device") {
                Button("Show RazerStream") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Test Device (LED Sweep)") {
                    deviceManager.testDevice()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!deviceManager.connected)

                Button("Redraw Page on Device") {
                    deviceManager.pushCurrentPage()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!deviceManager.connected)
            }

            CommandGroup(replacing: .help) {
                Button("RazerStream Help") { openWindow(id: "help") }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window("RazerStream Help", id: "help") {
            HelpView()
                .preferredColorScheme(colorScheme)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(deviceManager)
                .environmentObject(packManager)
                .preferredColorScheme(colorScheme)
        }

        MenuBarExtra {
            Text(deviceManager.connected
                 ? "Connected — fw \(deviceManager.firmware)"
                 : "No device")
            Divider()
            Picker("Appearance", selection: $appearanceMode) {
                Text("System").tag(0)
                Text("Light").tag(1)
                Text("Dark").tag(2)
            }
            Divider()
            Button("Show RazerStream") {
                AppActions.shared.showMainWindow?()
            }
            Button("Test Device (LED sweep)") {
                deviceManager.testDevice()
            }
            .disabled(!deviceManager.connected)
            Button("Push Page to Device") {
                deviceManager.pushCurrentPage()
            }
            Button("Quit RazerStream") {
                deviceManager.stop()
                NSApplication.shared.terminate(nil)
            }
        } label: {
            // Icon only; the live readout lives in the window status bar
            Image(nsImage: DeckIcon.menuBar)
        }
    }
}
